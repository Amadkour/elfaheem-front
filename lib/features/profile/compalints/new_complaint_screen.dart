// lib/features/profile/compalints/new_complaint_screen.dart
//
// The platform complaint form and the "my complaints" history (D-086 keeps the history on the hub page for most
// callers). Warm Editorial (D-610 – D-629): the sky hero block (the complaints subject, the same tone as the hub)
// is the one memorable element; every part of the form is a paper card on a warm hairline with a flat tinted icon
// tile, the editorial face on section titles, kit buttons, and tokens for every space, radius and type role.
// Colours come from the theme (context.colors), so light / dark and the admin palette follow. Logic is unchanged.
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_attachement_widgets.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_username.dart';
import 'package:flutter_education_app/design/app_mentions.dart';

class NewComplaintScreen extends StatefulWidget {
  const NewComplaintScreen({super.key, this.courseId, this.courseTitle, this.formOnly = false});

  final String? courseId;
  final String? courseTitle;

  /// Just the form, no "history" tab: the profile's Complaints page (D-086) keeps the history itself. A sent
  /// complaint pops the screen with the created [ComplaintModel].
  final bool formOnly;

  @override
  State<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends State<NewComplaintScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _suggestionCtrl = TextEditingController();

  ComplaintCategory _category = ComplaintCategory.general;
  // what / who it is about
  late String _targetType = widget.courseId != null ? 'course' : 'general';
  late int? _targetId = widget.courseId == null ? null : int.tryParse(widget.courseId!);
  late String? _targetLabel = widget.courseTitle;
  ComplaintPriority _priority = ComplaintPriority.medium;

  bool _suggestionExpanded = false;

  final Set<int> _expandedIds = {};
  final Set<int> _loadedIds = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (!widget.formOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ComplaintProvider>().loadComplaints(reset: true);
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _suggestionCtrl.dispose();
    super.dispose();
  }

  // `icon` is kept for the callers; the notice draws its own icon from `error`.
  void _snack(String message, Color color, IconData icon) => showAppNotice(message, error: color == context.colors.danger);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final p = context.read<ComplaintProvider>();
    final result = await p.createComplaint(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: complaintCategoryFor(_category, _targetType),
      priority: _priority,
      courseId: widget.courseId,
      targetType: _targetType,
      targetId: _targetType == 'general' ? null : _targetId,
      targetLabel: _targetLabel,
      suggestedSolution:
      _suggestionCtrl.text.trim().isEmpty ? null : _suggestionCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result != null) {
      _titleCtrl.clear();
      _descCtrl.clear();
      _suggestionCtrl.clear();
      setState(() {
        _category = ComplaintCategory.general;
        _priority = ComplaintPriority.medium;
        _suggestionExpanded = false;
      });
      _snack('complaint_sent_success'.tr, context.colors.success,
          Icons.check_circle_rounded);
      if (widget.formOnly) {
        Navigator.of(context).pop(result);
        return;
      }
      _tabs.animateTo(1);
    } else {
      _snack('error_try_again'.tr, context.colors.danger, Icons.error_rounded);
    }
  }

  Future<void> _toggle(int id) async {
    final p = context.read<ComplaintProvider>();
    if (_expandedIds.contains(id)) {
      setState(() => _expandedIds.remove(id));
    } else {
      setState(() => _expandedIds.add(id));
      if (!_loadedIds.contains(id)) {
        await p.loadDetail(id);
        if (mounted) setState(() => _loadedIds.add(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // re-translate when the language changes
    final p = context.watch<ComplaintProvider>();
    // a student's new complaint (redesign S-C, Stu1Comm?screen=newcomplaint): the chat area and the kit's top bar
    final student = Provider.of<MyAuthProvider?>(context, listen: false)?.currentUser?.role == 'student';
    final title = widget.formOnly ? 'chub_new'.tr : 'complaints_and_support'.tr;
    final page = BasePage(
      key: const ValueKey('new_complaint'),
      useWebCard: !student,
      width: AppWidth.reading,
      appBar: student ? AppHeader(title: title) : ScreenAppBar(title: title),
      child: SafeArea(
        child: Column(
          children: [
            if (!widget.formOnly) _TabBar(controller: _tabs, unreadCount: _unreadCount(p)),
            if (widget.formOnly) Expanded(child: _form(p)),
            if (!widget.formOnly)
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _form(p),
                  _HistoryTab(
                    provider: p,
                    expandedIds: _expandedIds,
                    loadedIds: _loadedIds,
                    onToggle: _toggle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return student ? AppAreaScope(area: AppArea.chat, child: page) : page;
  }

  Widget _form(ComplaintProvider p) => _FormTab(
        target: ComplaintTargetPicker(
          type: _targetType,
          id: _targetId,
          label: _targetLabel,
          onChanged: (type, id, label) => setState(() {
            _targetType = type;
            _targetId = id;
            _targetLabel = label;
          }),
        ),
        formKey: _formKey,
        titleCtrl: _titleCtrl,
        descCtrl: _descCtrl,
        suggestionCtrl: _suggestionCtrl,
        suggestionExpanded: _suggestionExpanded,
        category: _category,
        priority: _priority,
        courseTitle: widget.courseTitle,
        isSending: p.isSending || p.isUploadingImage,
        pendingAttachments: p.pendingAttachments,
        onCategoryChanged: (v) => setState(() => _category = v),
        onPriorityChanged: (v) => setState(() => _priority = v),
        onToggleSuggestion: () =>
            setState(() => _suggestionExpanded = !_suggestionExpanded),
        onSubmit: _submit,
        onPickGallery: () => p.pickComplaintImages(),
        onPickCamera: () => p.pickComplaintImageFromCamera(),
        onPickFile: () => p.pickComplaintFile(),
        onRemoveImage: (i) => p.removeComplaintImage(i),
      );

  int _unreadCount(ComplaintProvider p) =>
      p.complaints.where((c) => !c.isReadByUser).length;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Small shared building blocks
// ══════════════════════════════════════════════════════════════════════════════

/// A section's icon tile: a flat tint of the gradient's first colour with its readable ink (Warm Editorial: no
/// gradient washes, no glow — the tone carries it).
class _GradIcon extends StatelessWidget {
  const _GradIcon({required this.icon, required this.gradient, this.size = AppTouch.min - AppSpace.xs});

  final IconData icon;
  final LinearGradient gradient;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = gradient.colors.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.control - AppSpace.xxs),
      ),
      child: Icon(icon, color: c.blockAccentInk(tone, c.cardBg), size: AppIconSize.md),
    );
  }
}

/// Titled paper card that holds one part of the form (tone + warm hairline, no resting shadow).
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final LinearGradient gradient;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _GradIcon(icon: icon, gradient: gradient),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(title, style: AppType.section(context).copyWith(color: c.textDark))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}

/// The form's opening block (sky, the complaints subject): the editorial title, what happens next, and the course
/// the complaint is about on a paper chip.
class _Hero extends StatelessWidget {
  const _Hero({this.courseTitle});

  final String? courseTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasCourse = courseTitle != null && courseTitle!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppBlock(
        tone: AppBlockTone.sky,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: AppTouch.primary,
                height: AppTouch.primary,
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Icon(Icons.support_agent_rounded, color: b.accentInk(c.primary), size: AppIconSize.lg),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text('complaint_hero_title'.tr, style: AppType.headline(context).copyWith(color: b.ink)),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  Text('complaint_hero_sub'.tr, style: AppType.body(context).copyWith(color: b.muted)),
                ]),
              ),
            ]),
            if (hasCourse) ...[
              const SizedBox(height: AppSpace.md),
              Container(
                constraints: const BoxConstraints(minHeight: AppIconSize.xl),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: c.divider, width: AppBorder.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_rounded, size: AppIconSize.sm, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      'complaint_about_course'.tr.replaceAll('{course}', courseTitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
          ]);
        }),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  Tab bar
// ══════════════════════════════════════════════════════════════════════════════

class _TabBar extends StatelessWidget {
  const _TabBar({required this.controller, required this.unreadCount});

  final TabController controller;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = AppType.label(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.control - AppSpace.xxs),
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: c.divider.withValues(alpha: 0),
        labelColor: c.textDark,
        unselectedLabelColor: c.textMedium,
        labelStyle: label.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: label,
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_note_rounded, size: AppIconSize.md),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text('new_complaint_tab'.tr, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_rounded, size: AppIconSize.md),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text('my_complaints_tab'.tr, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (unreadCount > 0) ...[
                const SizedBox(width: AppSpace.xs),
                _Badge(count: unreadCount),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: AppIconSize.md),
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2, vertical: 1),
    decoration: BoxDecoration(
      color: context.colors.dangerBase,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: AppType.meta(context).copyWith(color: context.colors.onHero, fontWeight: FontWeight.w600),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Tab 0 — New complaint form
// ══════════════════════════════════════════════════════════════════════════════

class _FormTab extends StatelessWidget {
  final Widget? target;   // "about": general · course · teacher · student · staff · department
  const _FormTab({
    this.target,
    required this.formKey,
    required this.titleCtrl,
    required this.descCtrl,
    required this.suggestionCtrl,
    required this.suggestionExpanded,
    required this.category,
    required this.priority,
    required this.courseTitle,
    required this.isSending,
    required this.pendingAttachments,
    required this.onCategoryChanged,
    required this.onPriorityChanged,
    required this.onToggleSuggestion,
    required this.onSubmit,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickFile,
    required this.onRemoveImage,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController suggestionCtrl;
  final bool suggestionExpanded;
  final ComplaintCategory category;
  final ComplaintPriority priority;
  final String? courseTitle;
  final bool isSending;
  final List<PendingAttachment> pendingAttachments;
  final ValueChanged<ComplaintCategory> onCategoryChanged;
  final ValueChanged<ComplaintPriority> onPriorityChanged;
  final VoidCallback onToggleSuggestion;
  final VoidCallback onSubmit;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(courseTitle: courseTitle),
                if (target != null) target!,

                // ── Title ──────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.title_rounded,
                  gradient: c.primaryGradient,
                  title: 'complaint_title_label'.tr,
                  child: MyTextField(
                    controller: titleCtrl,
                    label: 'complaint_title_hint'.tr,
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'title_too_short'.tr
                        : null,
                  ),
                ),

                // ── Category ───────────────────────────────────────────
                ParentComponent(
                  featureKey: 'new_complaint.category',
                  child: _SectionCard(
                    icon: Icons.category_rounded,
                    gradient: c.goldCharcoalGradient,
                    title: 'category_label'.tr,
                    child: _CategoryPicker(
                        selected: category, onChanged: onCategoryChanged),
                  ),
                ),

                // ── Priority ───────────────────────────────────────────
                ParentComponent(
                  featureKey: 'new_complaint.priority',
                  child: _SectionCard(
                    icon: Icons.flag_rounded,
                    gradient: c.dangerGradient,
                    title: 'priority_label'.tr,
                    child: _PriorityPicker(
                        selected: priority, onChanged: onPriorityChanged),
                  ),
                ),

                // ── Description ────────────────────────────────────────
                _SectionCard(
                  icon: Icons.notes_rounded,
                  gradient: c.tealGradient,
                  title: 'detailed_description_label'.tr,
                  // "@" suggests the platform staff who will handle it (D-075)
                  child: Mentions(
                    controller: descCtrl,
                    source: MentionApi.source('complaint'),
                    child: MyTextField(
                      controller: descCtrl,
                      label: 'description_complaint_hint'.tr,
                      maxLine: 5,
                      validator: (v) => (v == null || v.trim().length < 10)
                          ? 'description_too_short'.tr
                          : null,
                    ),
                  ),
                ),

                // ── Attachments ────────────────────────────────────────
                ParentComponent(
                  featureKey: 'new_complaint.attachments',
                  child: _AttachmentSection(
                    attachments: pendingAttachments,
                    onPickGallery: onPickGallery,
                    onPickCamera: onPickCamera,
                    onPickFile: onPickFile,
                    onRemove: onRemoveImage,
                  ),
                ),

                // ── Suggested solution (optional, expandable) ──────────
                ParentComponent(
                  featureKey: 'new_complaint.suggested_solution',
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.lg),
                    child: _SuggestedSolutionField(
                      controller: suggestionCtrl,
                      isExpanded: suggestionExpanded,
                      onToggle: onToggleSuggestion,
                    ),
                  ),
                ),

                // ── Submit ─────────────────────────────────────────────
                AppButton.primary(
                  label: 'send_complaint_btn'.tr,
                  busy: isSending,
                  onPressed: isSending ? null : onSubmit,
                  icon: Icons.send_rounded,
                  size: AppButtonSize.lg,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Suggested solution — collapsible, success-coloured (the "idea" card)
// ══════════════════════════════════════════════════════════════════════════════

class _SuggestedSolutionField extends StatelessWidget {
  const _SuggestedSolutionField({
    required this.controller,
    required this.isExpanded,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool isExpanded;
  final VoidCallback onToggle;

  /// The field's length limit, shown under it.
  static const int _max = 2000;

  /// From here the counter turns to a warning.
  static const int _near = 1800;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final ink = c.blockAccentInk(c.success, isExpanded ? c.successTint : c.cardBg);
    final radius = BorderRadius.circular(AppRadius.card);

    return AnimatedContainer(
      duration: motion.slow,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: isExpanded ? c.successTint : c.cardBg,
        borderRadius: radius,
        border: Border.all(
          color: isExpanded ? c.success.withValues(alpha: 0.45) : c.divider,
          width: AppBorder.hairline,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: radius,
            child: Padding(
              padding: AppSpace.card,
              child: Row(children: [
                _GradIcon(icon: Icons.lightbulb_rounded, gradient: c.successGradient),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          'suggested_solution_label'.tr,
                          style: AppType.section(context).copyWith(color: c.textDark),
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 1),
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: c.divider, width: AppBorder.hairline),
                        ),
                        child: Text('optional'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
                      ),
                    ]),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text('suggested_solution_hint'.tr, style: AppType.meta(context).copyWith(color: c.textLight)),
                  ]),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: motion.slow,
                  curve: AppMotion.curve,
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: isExpanded ? ink : c.textLight),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: motion.slow,
            curve: AppMotion.curve,
            alignment: AlignmentDirectional.topStart,
            child: !isExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Divider(color: c.success.withValues(alpha: 0.25), height: AppBorder.hairline),
                      const SizedBox(height: AppSpace.sm),
                      MyTextField(
                        controller: controller,
                        maxLine: 3,
                        label: 'suggested_solution_placeholder'.tr,
                        // Optional field: empty is valid. The minimum length applies
                        // only once the person started typing.
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          if (v.trim().length < 5) return 'suggested__too_short'.tr;
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (_, v, _) => Text(
                            '${v.text.length} / $_max',
                            style: AppType.meta(context).copyWith(
                              color: v.text.length > _near ? c.blockAccentInk(c.warning, c.successTint) : c.textLight,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Tab 1 — History
// ══════════════════════════════════════════════════════════════════════════════

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.provider,
    required this.expandedIds,
    required this.loadedIds,
    required this.onToggle,
  });

  final ComplaintProvider provider;
  final Set<int> expandedIds;
  final Set<int> loadedIds;
  final Future<void> Function(int id) onToggle;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingList && provider.complaints.isEmpty) {
      return const AppListSkeleton();
    }
    if (provider.complaints.isEmpty && provider.errorMsg != null && provider.errorMsg != 'upload_failed') {
      return AppRefresh(
        onRefresh: () => provider.loadComplaints(reset: true),
        scrollable: false,
        child: ErrorRetry(message: provider.errorMsg!, onRetry: () => provider.loadComplaints(reset: true)),
      );
    }
    if (provider.complaints.isEmpty) {
      return AppRefresh(
        onRefresh: () => provider.loadComplaints(reset: true),
        scrollable: false,
        child: const _EmptyHistory(),
      );
    }

    final all = provider.complaints;
    final open = all
        .where((x) =>
    x.status == ComplaintStatus.open || x.status == ComplaintStatus.inProgress)
        .length;

    return AppRefresh(
      onRefresh: () => provider.loadComplaints(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
        itemCount: all.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _HistorySummary(total: all.length, open: open);
          final complaint = all[i - 1];
          final isExpanded = expandedIds.contains(complaint.id);
          final isLoaded = loadedIds.contains(complaint.id);
          final full = isLoaded
              ? all.firstWhere((c) => c.id == complaint.id, orElse: () => complaint)
              : complaint;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _ComplaintHistoryCard(
              complaint: full,
              isExpanded: isExpanded,
              isLoading: isExpanded && !isLoaded,
              onToggle: () => onToggle(complaint.id),
            ),
          );
        },
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.total, required this.open});

  final int total;
  final int open;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(c.radiusLarge),
      ),
      child: Row(children: [
        _GradIcon(icon: Icons.forum_rounded, gradient: c.primaryGradient, size: 40),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            'complaint_history_summary'
                .tr
                .replaceAll('{n}', '$total')
                .replaceAll('{open}', '$open'),
            style: c.h3.copyWith(fontSize: 14),
          ),
        ),
      ]),
    );
  }
}

class _ComplaintHistoryCard extends StatelessWidget {
  const _ComplaintHistoryCard({
    required this.complaint,
    required this.isExpanded,
    required this.isLoading,
    required this.onToggle,
  });

  final ComplaintModel complaint;
  final bool isExpanded;
  final bool isLoading;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusClr = _statusColor(c, complaint.status);
    final hasUnread = !complaint.isReadByUser;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        boxShadow: c.cardShadow,
        border: Border.all(
          color: isExpanded
              ? statusClr.withValues(alpha: 0.45)
              : hasUnread
              ? c.primary.withValues(alpha: 0.45)
              : c.divider,
          width: isExpanded || hasUnread ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(c.radiusLarge),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(children: [
                // priority stripe (start edge)
                Container(
                  width: 4,
                  height: 46,
                  margin: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                  decoration: BoxDecoration(
                    color: _priorityColor(c, complaint.priority),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          complaint.title,
                          style: c.h3.copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                          width: 8,
                          height: 8,
                          decoration:
                          BoxDecoration(color: c.primary, shape: BoxShape.circle),
                        ),
                      _StatusBadge(
                          label: _statusLabel(complaint.status), color: statusClr),
                    ]),
                    const SizedBox(height: AppSpace.xs),
                    Row(children: [
                      _CategoryBadge(
                        label: _categoryLabel(complaint.category),
                        primary: c.primary,
                        tint: c.primaryTint,
                      ),
                      if (complaint.suggestedSolution != null) ...[
                        const SizedBox(width: AppSpace.xs),
                        const _SuggestionBadge(),
                      ],
                      const Spacer(),
                      _RepliesCountChip(count: complaint.repliesCount),
                    ]),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: c.textLight),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState:
            isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: isLoading
                ? const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Center(child: AppLoadingIndicator()),
            )
                : _ExpandedBody(complaint: complaint),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ThemeConfigProvider c, ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => c.warning,
    ComplaintStatus.inProgress => c.primary,
    ComplaintStatus.resolved => c.success,
    ComplaintStatus.closed => c.textLight,
  };

  Color _priorityColor(ThemeConfigProvider c, ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => c.danger,
    ComplaintPriority.high => Color.lerp(c.warning, c.danger, 0.5)!,
    ComplaintPriority.medium => c.warning,
    ComplaintPriority.low => c.success,
  };

  String _statusLabel(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => 'status_open'.tr,
    ComplaintStatus.inProgress => 'status_in_progress'.tr,
    ComplaintStatus.resolved => 'status_resolved'.tr,
    ComplaintStatus.closed => 'status_closed'.tr,
  };

  String _categoryLabel(ComplaintCategory cat) => switch (cat) {
    ComplaintCategory.technical => 'category_technical'.tr,
    ComplaintCategory.payment => 'category_payment'.tr,
    ComplaintCategory.courseContent => 'category_content'.tr,
    ComplaintCategory.teacher => 'category_teacher'.tr,
    ComplaintCategory.student => 'category_student'.tr,
    ComplaintCategory.general => 'category_general'.tr,
  };
}

class _SuggestionBadge extends StatelessWidget {
  const _SuggestionBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lightbulb_rounded, size: 11, color: c.success),
        const SizedBox(width: AppSpace.xxs),
        Text(
          'has_suggestion'.tr,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.success,
          ),
        ),
      ]),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.complaint});

  final ComplaintModel complaint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: c.divider, height: 1),
        const SizedBox(height: AppSpace.sm),
        Text(complaint.description, style: c.body.copyWith(height: 1.7)),
        if (complaint.suggestedSolution != null) ...[
          const SizedBox(height: AppSpace.md),
          _SuggestedSolutionBlock(text: complaint.suggestedSolution!),
        ],
        if (complaint.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          _AttachmentGallery(attachments: complaint.attachments),
        ],
        if (complaint.resolvedAt != null) ...[
          const SizedBox(height: AppSpace.sm),
          _ResolvedBanner(resolvedAt: complaint.resolvedAt!),
        ],
        if (complaint.replies.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text('replies_label'.tr, style: c.h3.copyWith(fontSize: 13)),
          const SizedBox(height: AppSpace.sm),
          ...complaint.replies.map((r) => _HistoryReplyBubble(reply: r)),
        ],
      ]),
    );
  }
}

class _SuggestedSolutionBlock extends StatelessWidget {
  const _SuggestedSolutionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_rounded, size: 16, color: c.success),
          const SizedBox(width: AppSpace.xs),
          Text(
            'suggested_solution_label'.tr,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.success,
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(text, style: c.body.copyWith(fontSize: 13, height: 1.6, color: c.textDark)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Attachments (form)
// ══════════════════════════════════════════════════════════════════════════════

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickFile,
    required this.onRemove,
  });

  final List<PendingAttachment> attachments;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;
  final ValueChanged<int> onRemove;

  static const int _max = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canAdd = attachments.length < _max;
    return _SectionCard(
      icon: Icons.attach_file_rounded,
      gradient: c.accentGradient,
      title: 'attachments_label'.tr,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '${attachments.length} / $_max',
          style: AppType.meta(context).copyWith(
            color: c.textMedium,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          ...attachments.asMap().entries.map(
                (e) => _AttachmentThumb(
              index: e.key,
              attachment: e.value,
              onRemove: onRemove,
            ),
          ),
          if (canAdd)
            _AddImageButton(
              onPickGallery: onPickGallery,
              onPickCamera: onPickCamera,
              onPickFile: onPickFile,
            ),
        ]),
        if (attachments.isEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text('attachments_hint'.tr, style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
      ]),
    );
  }
}

/// The side of an attachment thumbnail and of the "add" tile.
const double _thumb = AppTouch.min * 1.75;

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final PendingAttachment attachment;
  final ValueChanged<int> onRemove;

  bool get _isPdf =>
      attachment.file.name.toLowerCase().endsWith('.pdf') ||
          attachment.localPreviewUrl.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(clipBehavior: Clip.none, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: _isPdf
            ? Container(
          width: _thumb,
          height: _thumb,
          color: c.inputBg,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.picture_as_pdf_rounded, size: AppIconSize.lg, color: c.blockAccentInk(c.danger, c.inputBg)),
            const SizedBox(height: AppSpace.xxs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: Text(
                attachment.file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.overline(context).copyWith(color: c.textMedium),
              ),
            ),
          ]),
        )
            : kIsWeb
            ? Image.network(attachment.localPreviewUrl,
            width: _thumb, height: _thumb, fit: BoxFit.cover)
            : Image.file(File(attachment.localPreviewUrl),
            width: _thumb, height: _thumb, fit: BoxFit.cover),
      ),
      // the remove badge sits inside the corner (a target outside the thumb would not be hit-tested)
      PositionedDirectional(
        top: 0,
        end: 0,
        child: Semantics(
          button: true,
          label: 'delete'.tr,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onRemove(index),
            child: SizedBox(
              width: AppTouch.min - AppSpace.xs,
              height: AppTouch.min - AppSpace.xs,
              child: Center(
                child: Container(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  decoration: BoxDecoration(
                    color: c.dangerBase,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.cardBg, width: AppBorder.focus),
                  ),
                  child: Icon(Icons.close_rounded, size: AppIconSize.xs, color: c.onHero),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickFile,
  });

  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.blockAccentInk(c.primary, c.inputBg);
    final radius = BorderRadius.circular(AppRadius.control);
    return Material(
      color: c.inputBg,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      child: InkWell(
        borderRadius: radius,
        onTap: () => _show(context),
        child: SizedBox(
          width: _thumb,
          height: _thumb,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_photo_alternate_rounded, size: AppIconSize.lg, color: ink),
            const SizedBox(height: AppSpace.xxs),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                child: Text(
                  'add_attachment'.tr,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    final c = context.colors;
    showAppModalSheet(
      useSafeArea: true,
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // The browser file picker already covers "gallery" on web.
            if (!kIsWeb)
              _option(context, Icons.photo_library_rounded, c.primaryGradient,
                  'pick_from_gallery'.tr, onPickGallery),
            if (!kIsWeb)
              _option(context, Icons.camera_alt_rounded, c.goldCharcoalGradient,
                  'take_photo'.tr, onPickCamera),
            _option(context, Icons.folder_open_rounded, c.tealGradient,
                'browse_file_pdf_or_image'.tr, onPickFile),
          ]),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, IconData icon, LinearGradient g, String label,
      VoidCallback onTap) {
    final c = context.colors;
    return ListTile(
      minTileHeight: AppTouch.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      leading: _GradIcon(icon: icon, gradient: g),
      title: Text(label, style: AppType.row(context).copyWith(color: c.textDark)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Attachments / replies (history)
// ══════════════════════════════════════════════════════════════════════════════

class _AttachmentGallery extends StatelessWidget {
  const _AttachmentGallery({required this.attachments});

  final List<ComplaintAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'attachments_label'.tr,
        style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.textLight),
      ),
      const SizedBox(height: AppSpace.xs),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: attachments
            .map((a) => NetworkAttachmentTile(attachment: a, size: 70))
            .toList(),
      ),
    ]);
  }
}

class _HistoryReplyBubble extends StatelessWidget {
  const _HistoryReplyBubble({required this.reply});

  final ComplaintReply reply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isAdmin = reply.isAdmin;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        mainAxisAlignment: isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: c.primary.withValues(alpha: 0.15),
              backgroundImage:
              reply.senderImage != null ? NetworkImage(reply.senderImage!) : null,
              child: reply.senderImage == null
                  ? Icon(Icons.support_agent_rounded, size: 15, color: c.primary)
                  : null,
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: isAdmin ? c.primaryTint : null,
                gradient: isAdmin ? null : c.primaryGradient,
                borderRadius: BorderRadiusDirectional.only(
                  topStart: const Radius.circular(16),
                  topEnd: const Radius.circular(16),
                  bottomStart: Radius.circular(isAdmin ? 4 : 16),
                  bottomEnd: Radius.circular(isAdmin ? 16 : 4),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                    child: Text(
                      reply.senderName,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: c.primary,
                      ),
                    ),
                  ),
                Text(
                  reply.message,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 13,
                    height: 1.5,
                    color: isAdmin ? c.textDark : context.colors.onHero,
                  ),
                ),
                if (reply.attachments.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: reply.attachments
                        .map((a) => NetworkAttachmentTile(attachment: a, size: 70))
                        .toList(),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedBanner extends StatelessWidget {
  const _ResolvedBanner({required this.resolvedAt});

  final DateTime resolvedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_rounded, size: 18, color: c.success),
        const SizedBox(width: AppSpace.xs),
        Text(
          '${'resolved_at_prefix'.tr} ${AppTime.date(resolvedAt)}',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 12.5,
            color: c.success,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: c.primaryShadow,
            ),
            child: Icon(Icons.inbox_rounded, size: 44, color: context.colors.onHero),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('no_previous_complaints'.tr,
              textAlign: TextAlign.center, style: c.h2.copyWith(fontSize: 16)),
          const SizedBox(height: AppSpace.xs),
          Text('complaints_appear_after_send'.tr,
              textAlign: TextAlign.center, style: c.caption.copyWith(height: 1.5)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Badges
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.28)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpace.xxs),
      Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ]),
  );
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({
    required this.label,
    required this.primary,
    required this.tint,
  });

  final String label;
  final Color primary;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
    ),
  );
}

class _RepliesCountChip extends StatelessWidget {
  const _RepliesCountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.chat_bubble_outline_rounded, size: 14, color: c.textLight),
      const SizedBox(width: AppSpace.xxs),
      Text('$count', style: c.caption.copyWith(fontSize: 11.5)),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Pickers
// ══════════════════════════════════════════════════════════════════════════════

/// The category sent with a complaint. The form asks WHO it is about ("About what?") and WHAT KIND of problem it is
/// separately, so the kind picker no longer repeats teacher / student (M23); a general problem about a teacher or a
/// student is still filed under that category, as before.
ComplaintCategory complaintCategoryFor(ComplaintCategory picked, String targetType) {
  if (picked != ComplaintCategory.general) return picked;
  return switch (targetType) {
    'teacher' => ComplaintCategory.teacher,
    'student' => ComplaintCategory.student,
    _ => picked,
  };
}

/// The kinds of problem the picker offers (who it is about is the "About what?" picker's job, M23).
const kComplaintKinds = [
  ComplaintCategory.general,
  ComplaintCategory.technical,
  ComplaintCategory.payment,
  ComplaintCategory.courseContent,
];

/// One choice of a picker: paper at rest, the primary filled when chosen (the selection colour, system.md §2).
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final ink = selected ? c.onHero : c.textMedium;
    final radius = BorderRadius.circular(AppRadius.control);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.cardBg,
            borderRadius: radius,
            border: Border.all(color: selected ? c.primary : c.divider, width: AppBorder.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: AppIconSize.sm, color: selected ? c.onHero : c.textLight),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final ComplaintCategory selected;
  final ValueChanged<ComplaintCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ComplaintCategory.general: ('category_general'.tr, Icons.help_outline_rounded),
      ComplaintCategory.technical: ('category_technical'.tr, Icons.bug_report_outlined),
      ComplaintCategory.payment: ('category_payment'.tr, Icons.payment_outlined),
      ComplaintCategory.courseContent: ('category_content'.tr, Icons.book_outlined),
      ComplaintCategory.teacher: ('category_teacher'.tr, Icons.person_outline_rounded),
      ComplaintCategory.student: ('category_student'.tr, Icons.school_outlined),
    };
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: kComplaintKinds.map((cat) {
        final (label, icon) = labels[cat]!;
        return _ChoicePill(label: label, icon: icon, selected: selected == cat, onTap: () => onChanged(cat));
      }).toList(),
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker({required this.selected, required this.onChanged});

  final ComplaintPriority selected;
  final ValueChanged<ComplaintPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final meta = {
      ComplaintPriority.low: ('priority_low'.tr, c.success, Icons.arrow_downward_rounded),
      ComplaintPriority.medium: ('priority_medium'.tr, c.warning, Icons.remove_rounded),
      ComplaintPriority.high: (
      'priority_high'.tr,
      Color.lerp(c.warning, c.danger, 0.5)!,
      Icons.arrow_upward_rounded,
      ),
      ComplaintPriority.urgent: (
      'priority_urgent'.tr,
      c.danger,
      Icons.priority_high_rounded,
      ),
    };
    final items = ComplaintPriority.values;
    final radius = BorderRadius.circular(AppRadius.control);
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Builder(builder: (_) {
            final (label, color, icon) = meta[items[i]]!;
            final sel = selected == items[i];
            // the tone as text: readable on its own faint tint at rest; white on the filled tone when chosen
            final ink = sel ? c.onHero : c.blockAccentInk(color, c.cardBg);
            final fill = sel ? c.blockAccentInk(color, c.onHero) : color.withValues(alpha: 0.08);
            return Semantics(
              button: true,
              selected: sel,
              child: InkWell(
                borderRadius: radius,
                onTap: () => onChanged(items[i]),
                child: AnimatedContainer(
                  duration: motion.fast,
                  curve: AppMotion.curve,
                  constraints: const BoxConstraints(minHeight: AppTouch.primary),
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: radius,
                    border: Border.all(color: sel ? fill : color.withValues(alpha: 0.35), width: AppBorder.hairline),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: AppIconSize.sm, color: ink),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ],
    ]);
  }
}

/// "What is this about?" — general, or a course / teacher / student / staff member / department of YOUR world.
class ComplaintTargetPicker extends StatefulWidget {
  const ComplaintTargetPicker({super.key, required this.type, this.id, this.label, required this.onChanged});
  final String type;
  final int? id;
  final String? label;
  final void Function(String type, int? id, String? label) onChanged;

  @override
  State<ComplaintTargetPicker> createState() => _ComplaintTargetPickerState();
}

class _ComplaintTargetPickerState extends State<ComplaintTargetPicker> {
  Map<String, List<Map<String, dynamic>>> _cache = {};

  static const _types = [
    ('general', Icons.public_rounded, 'complaint_about_general'),
    ('course', Icons.menu_book_rounded, 'complaint_about_course_t'),
    ('teacher', Icons.person_pin_rounded, 'complaint_about_teacher'),
    ('student', Icons.school_rounded, 'complaint_about_student'),
    ('staff', Icons.support_agent_rounded, 'complaint_about_staff'),
    ('department', Icons.apartment_rounded, 'complaint_about_department'),
  ];

  Future<void> _pick(String type) async {
    if (type == 'general') return widget.onChanged('general', null, null);
    var items = _cache[type];
    if (items == null) {
      try {
        final r = await ApiClient().get('/api/v1/complaints/targets', queryParams: {'type': type});
        items = [for (final x in ((r as Map)['items'] as List)) Map<String, dynamic>.from(x as Map)];
        _cache = {..._cache, type: items};
      } catch (_) {
        items = const [];
      }
    }
    if (!mounted) return;
    if (items.isEmpty) {
      showAppNotice('complaint_about_none'.tr, error: true);
      return;
    }
    final picked = await showAppModalSheet<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => AppSheetContent(title: _types.firstWhere((x) => x.$1 == type).$3.tr, children: [
        for (final x in items!)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              minTileHeight: AppTouch.min + AppSpace.xs,
              title: Text('${x['label']}', style: AppType.row(ctx).copyWith(color: ctx.colors.textDark)),
              subtitle: usernameFrom(x) == null ? null : AppUsernameLine(usernameFrom(x)),
              onTap: () => Navigator.pop(ctx, x),
            ),
          ),
      ]),
    );
    if (picked != null) widget.onChanged(type, (picked['id'] as num).toInt(), '${picked['label']}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chosen = widget.type != 'general' && (widget.label ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('complaint_about'.tr, style: AppType.section(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final x in _types)
            _ChoicePill(label: x.$3.tr, icon: x.$2, selected: widget.type == x.$1, onTap: () => _pick(x.$1)),
        ]),
        if (chosen)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: AppCard(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
              child: Row(children: [
                Icon(_types.firstWhere((x) => x.$1 == widget.type).$2, color: hubSafeInk(c), size: AppIconSize.md),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('${widget.label}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                ),
                AppButton.ghost(label: 'change'.tr, onPressed: () => _pick(widget.type)),
              ]),
            ),
          ),
      ]),
    );
  }

  /// The primary as an icon on paper, lifted in dark mode where it is too dark.
  static Color hubSafeInk(ThemeConfigProvider c) => c.blockAccentInk(c.primary, c.cardBg);
}
