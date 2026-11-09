// lib/features/shared/profile/compalints/new_complaint_screen.dart
//
// Redesign: every colour, gradient, shadow and radius comes from YOUR theme
// (context.colors) — no hard-coded hex values — so it follows light / dark mode
// and the palette the admin edits. Logic is unchanged.
//
//   • hero banner (+ the course the complaint is about)
//   • each part of the form is a titled card with a gradient icon
//   • gradient pill tab bar, friendly pickers, themed status colours
//   • RTL-safe (start/end instead of left/right) and re-translates live
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh, AppTime;
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import 'complaint_attachement_widgets.dart';
import 'complaint_model.dart';
import 'complaint_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_username.dart';
import 'package:flutter_education_app/design/app_mentions.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/design/app_kit.dart' show AppSheetContent;

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
    return BasePage(
      key: const ValueKey('new_complaint'),
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: widget.formOnly ? 'chub_new'.tr : 'complaints_and_support'.tr),
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

/// Gradient rounded-square icon (same language as the admin area).
class _GradIcon extends StatelessWidget {
  const _GradIcon({required this.icon, required this.gradient, this.size = 38});

  final IconData icon;
  final LinearGradient gradient;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(size * 0.36),
      boxShadow: [
        BoxShadow(
          color: gradient.colors.last.withValues(alpha: 0.24),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Icon(icon, color: context.colors.onHero, size: size * 0.52),
  );
}

/// Titled card that holds one part of the form.
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _GradIcon(icon: icon, gradient: gradient, size: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: c.h3.copyWith(fontSize: 15))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Friendly banner at the top of the form.
class _Hero extends StatelessWidget {
  const _Hero({this.courseTitle});

  final String? courseTitle;

  Widget _blob(BuildContext context, double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.colors.onHero.withValues(alpha: alpha),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasCourse = courseTitle != null && courseTitle!.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: c.primaryShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(children: [
          PositionedDirectional(end: -30, top: -30, child: _blob(context, 130, 0.10)),
          PositionedDirectional(start: -24, bottom: -44, child: _blob(context, 110, 0.08)),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: context.colors.onHero.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.support_agent_rounded,
                      color: context.colors.onHero, size: 29),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'complaint_hero_title'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: context.colors.onHero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'complaint_hero_sub'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 12.5,
                        height: 1.5,
                        color: context.colors.onHero.withValues(alpha: 0.9),
                      ),
                    ),
                  ]),
                ),
              ]),
              if (hasCourse) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.onHero.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.menu_book_rounded, size: 14, color: context.colors.onHero),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'complaint_about_course'.tr.replaceAll('{course}', courseTitle!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.colors.onHero,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(15),
          boxShadow: c.primaryShadow,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: context.colors.onHero,
        unselectedLabelColor: c.textMedium,
        labelStyle: TextStyle(
            fontFamily: AppFonts.display, fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: AppFonts.display, fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_note_rounded, size: 18),
              const SizedBox(width: 6),
              Text('new_complaint_tab'.tr),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 6),
              Text('my_complaints_tab'.tr),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
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
    constraints: const BoxConstraints(minWidth: 18),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.colors.danger,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: context.colors.onHero,
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          if (target != null) target!,
                _Hero(courseTitle: courseTitle),

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
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _SuggestedSolutionField(
                      controller: suggestionCtrl,
                      isExpanded: suggestionExpanded,
                      onToggle: onToggleSuggestion,
                    ),
                  ),
                ),

                // ── Submit ─────────────────────────────────────────────
                PrimaryButton(
                  label: 'send_complaint_btn'.tr,
                  isLoading: isSending,
                  onPressed: onSubmit,
                  icon: Icons.send_rounded,
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = c.success;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isExpanded ? c.successTint : c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        border: Border.all(
          color: isExpanded ? accent.withValues(alpha: 0.55) : c.divider,
          width: 1.5,
        ),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(c.radiusLarge),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _GradIcon(
                  icon: Icons.lightbulb_rounded,
                  gradient: c.successGradient,
                  size: 38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          'suggested_solution_label'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isExpanded ? accent : c.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'optional'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text('suggested_solution_hint'.tr,
                        style: c.caption.copyWith(fontSize: 11.5)),
                  ]),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: isExpanded ? accent : c.textLight),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 280),
            crossFadeState:
            isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Divider(color: accent.withValues(alpha: 0.25), height: 1),
                const SizedBox(height: 12),
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
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, v, _) => Text(
                      '${v.text.length} / 2000',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 11,
                        color: v.text.length > 1800 ? c.warning : c.textLight,
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
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
            padding: const EdgeInsets.only(bottom: 12),
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(c.radiusLarge),
      ),
      child: Row(children: [
        _GradIcon(icon: Icons.forum_rounded, gradient: c.primaryGradient, size: 40),
        const SizedBox(width: 12),
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
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                // priority stripe (start edge)
                Container(
                  width: 4,
                  height: 46,
                  margin: const EdgeInsetsDirectional.only(end: 12),
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
                          margin: const EdgeInsetsDirectional.only(end: 6),
                          width: 8,
                          height: 8,
                          decoration:
                          BoxDecoration(color: c.primary, shape: BoxShape.circle),
                        ),
                      _StatusBadge(
                          label: _statusLabel(complaint.status), color: statusClr),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _CategoryBadge(
                        label: _categoryLabel(complaint.category),
                        primary: c.primary,
                        tint: c.primaryTint,
                      ),
                      if (complaint.suggestedSolution != null) ...[
                        const SizedBox(width: 6),
                        const _SuggestionBadge(),
                      ],
                      const Spacer(),
                      _RepliesCountChip(count: complaint.repliesCount),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
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
              padding: EdgeInsets.all(20),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lightbulb_rounded, size: 11, color: c.success),
        const SizedBox(width: 3),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: c.divider, height: 1),
        const SizedBox(height: 12),
        Text(complaint.description, style: c.body.copyWith(height: 1.7)),
        if (complaint.suggestedSolution != null) ...[
          const SizedBox(height: 14),
          _SuggestedSolutionBlock(text: complaint.suggestedSolution!),
        ],
        if (complaint.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AttachmentGallery(attachments: complaint.attachments),
        ],
        if (complaint.resolvedAt != null) ...[
          const SizedBox(height: 12),
          _ResolvedBanner(resolvedAt: complaint.resolvedAt!),
        ],
        if (complaint.replies.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('replies_label'.tr, style: c.h3.copyWith(fontSize: 13)),
          const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_rounded, size: 16, color: c.success),
          const SizedBox(width: 6),
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
        const SizedBox(height: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${attachments.length} / $_max',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.textMedium,
          ),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
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
          const SizedBox(height: 10),
          Text('attachments_hint'.tr,
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 12, color: c.textLight)),
        ],
      ]),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final PendingAttachment attachment;
  final ValueChanged<int> onRemove;
  static const double _size = 84;

  bool get _isPdf =>
      attachment.file.name.toLowerCase().endsWith('.pdf') ||
          attachment.localPreviewUrl.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(clipBehavior: Clip.none, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _isPdf
            ? Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(gradient: c.primaryGradient),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.picture_as_pdf_rounded, size: 28, color: context.colors.onHero),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                attachment.file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppFonts.display, fontSize: 9, color: context.colors.onHero),
              ),
            ),
          ]),
        )
            : kIsWeb
            ? Image.network(attachment.localPreviewUrl,
            width: _size, height: _size, fit: BoxFit.cover)
            : Image.file(File(attachment.localPreviewUrl),
            width: _size, height: _size, fit: BoxFit.cover),
      ),
      PositionedDirectional(
        top: -6,
        end: -6,
        child: GestureDetector(
          onTap: () => onRemove(index),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c.danger,
              shape: BoxShape.circle,
              border: Border.all(color: c.cardBg, width: 2),
            ),
            child: Icon(Icons.close_rounded, size: 14, color: context.colors.onHero),
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
  static const double _size = 84;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _show(context),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: c.primaryTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_photo_alternate_rounded, size: 28, color: c.primary),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              'add_attachment'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
          ),
        ]),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
      leading: _GradIcon(icon: icon, gradient: g, size: 42),
      title: Text(
        label,
        style: TextStyle(
            fontFamily: AppFonts.display, fontWeight: FontWeight.w700, color: c.textDark),
      ),
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
      const SizedBox(height: 8),
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
      padding: const EdgeInsets.only(bottom: 8),
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
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
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
                    padding: const EdgeInsets.only(bottom: 3),
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
                  const SizedBox(height: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_rounded, size: 18, color: c.success),
        const SizedBox(width: 8),
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
        padding: const EdgeInsets.all(32),
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
          const SizedBox(height: 20),
          Text('no_previous_complaints'.tr,
              textAlign: TextAlign.center, style: c.h2.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
      const SizedBox(width: 5),
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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
      const SizedBox(width: 4),
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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final ComplaintCategory selected;
  final ValueChanged<ComplaintCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = {
      ComplaintCategory.general: ('category_general'.tr, Icons.help_outline_rounded),
      ComplaintCategory.technical: ('category_technical'.tr, Icons.bug_report_outlined),
      ComplaintCategory.payment: ('category_payment'.tr, Icons.payment_outlined),
      ComplaintCategory.courseContent: ('category_content'.tr, Icons.book_outlined),
      ComplaintCategory.teacher: ('category_teacher'.tr, Icons.person_outline_rounded),
      ComplaintCategory.student: ('category_student'.tr, Icons.school_outlined),
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kComplaintKinds.map((cat) {
        final (label, icon) = labels[cat]!;
        final sel = selected == cat;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? null : c.inputBg,
              gradient: sel ? c.primaryGradient : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sel ? Colors.transparent : c.divider, width: 1.2),
              boxShadow: sel ? c.primaryShadow : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: sel ? context.colors.onHero : c.textLight),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: sel ? context.colors.onHero : c.textMedium,
                ),
              ),
            ]),
          ),
        );
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
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Builder(builder: (_) {
            final (label, color, icon) = meta[items[i]]!;
            final sel = selected == items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(items[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? color : color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: sel ? color : color.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: sel ? context.colors.onHero : color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: sel ? context.colors.onHero : color,
                    ),
                  ),
                ]),
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
              title: Text('${x['label']}', style: TextStyle(fontFamily: AppFonts.family)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('complaint_about'.tr, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, color: c.textDark)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in _types)
            ChoiceChip(
              avatar: Icon(x.$2, size: 17, color: widget.type == x.$1 ? c.primary : c.textMedium),
              label: Text(x.$3.tr, style: TextStyle(fontFamily: AppFonts.family)),
              selected: widget.type == x.$1,
              onSelected: (_) => _pick(x.$1),
            ),
        ]),
        if (widget.type != 'general' && (widget.label ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.primary.withValues(alpha: 0.25))),
              child: Row(children: [
                Icon(_types.firstWhere((x) => x.$1 == widget.type).$2, color: c.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${widget.label}', style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700, color: c.textDark))),
                TextButton(onPressed: () => _pick(widget.type), child: Text('change'.tr)),
              ]),
            ),
          ),
      ]),
    );
  }
}
