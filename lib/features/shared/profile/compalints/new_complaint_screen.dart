// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/new_complaint_screen.dart
// New complaint form  +  user's previous complaints with replies inline
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import '../../../auth/auth_widgets.dart';
import 'complaint_model.dart';
import 'complaint_provider.dart';

class NewComplaintScreen extends StatefulWidget {
  const NewComplaintScreen({super.key, this.courseId, this.courseTitle});
  final String? courseId;
  final String? courseTitle;

  @override
  State<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends State<NewComplaintScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _formKey   = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  ComplaintCategory _category = ComplaintCategory.general;
  ComplaintPriority _priority = ComplaintPriority.medium;

  final Set<int> _expandedIds = {};
  final Set<int> _loadedIds   = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComplaintProvider>().loadComplaints(reset: true);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final p = context.read<ComplaintProvider>();
    final result = await p.createComplaint(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category,
      priority: _priority,
      courseId: widget.courseId,
    );
    if (!mounted) return;
    if (result != null) {
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _category = ComplaintCategory.general;
        _priority = ComplaintPriority.medium;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('complaint_sent_success'.tr,
            style: const TextStyle(fontFamily: 'bahji')),
        backgroundColor: context.themeConfig.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      _tabs.animateTo(1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('error_try_again'.tr,
            style: const TextStyle(fontFamily: 'bahji')),
        backgroundColor: context.themeConfig.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
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
    final p = context.watch<ComplaintProvider>();

    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(children: [
          ScreenAppBar(title: 'complaints_and_support'.tr),
          _TabBar(controller: _tabs, unreadCount: _unreadCount(p)),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // ── Tab 0: New complaint form ──────────────────────────────
                _FormTab(
                  formKey: _formKey,
                  titleCtrl: _titleCtrl,
                  descCtrl: _descCtrl,
                  category: _category,
                  priority: _priority,
                  courseTitle: widget.courseTitle,
                  isSending: p.isSending,
                  pendingAttachments: p.pendingAttachments,
                  onCategoryChanged: (v) => setState(() => _category = v),
                  onPriorityChanged: (v) => setState(() => _priority = v),
                  onSubmit: _submit,
                  onPickGallery: () => p.pickComplaintImages(),
                  onPickCamera: () => p.pickComplaintImageFromCamera(),
                  onRemoveImage: (i) => p.removeComplaintImage(i),
                ),

                // ── Tab 1: Previous complaints ──────────────────────────
                _HistoryTab(
                  provider: p,
                  expandedIds: _expandedIds,
                  loadedIds: _loadedIds,
                  onToggle: _toggle,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  int _unreadCount(ComplaintProvider p) =>
      p.complaints.where((c) => !c.isReadByUser).length;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Custom Tab Bar
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: c.cardShadow,
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(11),
          boxShadow: c.primaryShadow,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: c.textMedium,
        labelStyle: const TextStyle(
            fontFamily: 'bahji', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'bahji', fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_circle_outline_rounded, size: 16),
              const SizedBox(width: 6),
              Text('new_complaint_tab'.tr),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_rounded, size: 16),
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            fontFamily: 'bahji',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Tab 0 — New Complaint Form
// ══════════════════════════════════════════════════════════════════════════════

class _FormTab extends StatelessWidget {
  const _FormTab({
    required this.formKey,
    required this.titleCtrl,
    required this.descCtrl,
    required this.category,
    required this.priority,
    required this.courseTitle,
    required this.isSending,
    required this.pendingAttachments,
    required this.onCategoryChanged,
    required this.onPriorityChanged,
    required this.onSubmit,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemoveImage,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final ComplaintCategory category;
  final ComplaintPriority priority;
  final String? courseTitle;
  final bool isSending;
  final List<PendingAttachment> pendingAttachments;
  final ValueChanged<ComplaintCategory> onCategoryChanged;
  final ValueChanged<ComplaintPriority> onPriorityChanged;
  final VoidCallback onSubmit;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Form(
        key: formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Course badge ─────────────────────────────────────────────────
          if (courseTitle != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.accentTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.book_outlined, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(courseTitle!,
                      style: TextStyle(
                          fontFamily: 'bahji',
                          color: c.accent,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // ── Title ────────────────────────────────────────────────────────
          _Label(text: 'complaint_title_label'.tr),
          const SizedBox(height: 8),
          MyTextField(
            controller: titleCtrl,
            label: 'complaint_title_hint'.tr,
            validator: (v) =>
            (v == null || v.trim().length < 5) ? 'title_too_short'.tr : null,
          ),
          const SizedBox(height: 20),

          // ── Category ─────────────────────────────────────────────────────
          _Label(text: 'category_label'.tr),
          const SizedBox(height: 8),
          _CategoryPicker(selected: category, onChanged: onCategoryChanged),
          const SizedBox(height: 20),

          // ── Priority ─────────────────────────────────────────────────────
          _Label(text: 'priority_label'.tr),
          const SizedBox(height: 8),
          _PriorityPicker(selected: priority, onChanged: onPriorityChanged),
          const SizedBox(height: 20),

          // ── Description ──────────────────────────────────────────────────
          _Label(text: 'detailed_description_label'.tr),
          const SizedBox(height: 8),
          MyTextField(
            controller: descCtrl,
            label: 'description_complaint_hint'.tr,
            maxLine: 6,
            validator: (v) => (v == null || v.trim().length < 10)
                ? 'description_too_short'.tr
                : null,
          ),
          const SizedBox(height: 20),

          // ── Attachments section ──────────────────────────────────────────
          _AttachmentSection(
            attachments: pendingAttachments,
            onPickGallery: onPickGallery,
            onPickCamera: onPickCamera,
            onRemove: onRemoveImage,
          ),
          const SizedBox(height: 32),

          // ── Submit ───────────────────────────────────────────────────────
          PrimaryButton(
            label: 'send_complaint_btn'.tr,
            isLoading: isSending,
            onPressed: onSubmit,
            icon: Icons.send_rounded,
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Attachment Section  — reused in both the form and the reply input
// ══════════════════════════════════════════════════════════════════════════════

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemove,
    this.compact = false,
  });

  final List<PendingAttachment> attachments;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final ValueChanged<int> onRemove;

  /// When true, renders a single-row strip (used inside the reply bar).
  final bool compact;

  static const int _max = 4;

  @override
  Widget build(BuildContext context) {
    final c      = context.colors;
    final canAdd = attachments.length < _max;

    if (compact) {
      return _CompactAttachmentStrip(
        attachments: attachments,
        canAdd: canAdd,
        onPickGallery: onPickGallery,
        onPickCamera: onPickCamera,
        onRemove: onRemove,
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ─────────────────────────────────────────────────────────
      Row(children: [
        _Label(text: 'attachments_label'.tr),
        const Spacer(),
        Text(
          '${attachments.length} / $_max',
          style: TextStyle(
              fontFamily: 'bahji', fontSize: 12, color: c.textLight),
        ),
      ]),
      const SizedBox(height: 10),

      // ── Image grid + add button ─────────────────────────────────────────
      Wrap(spacing: 10, runSpacing: 10, children: [
        // Existing thumbnails
        ...attachments.asMap().entries.map((e) => _AttachmentThumb(
          index: e.key,
          attachment: e.value,
          onRemove: onRemove,
        )),

        // Add button (hidden when max reached)
        if (canAdd)
          _AddImageButton(
            onPickGallery: onPickGallery,
            onPickCamera: onPickCamera,
          ),
      ]),

      if (attachments.isEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'attachments_hint'.tr, // e.g. "Attach up to 4 images (optional)"
          style: TextStyle(
              fontFamily: 'bahji', fontSize: 12, color: c.textLight),
        ),
      ],
    ]);
  }
}

// ── Single thumbnail with ×-remove ───────────────────────────────────────────

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final PendingAttachment attachment;
  final ValueChanged<int> onRemove;

  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: kIsWeb
              ? Image.network(
            attachment.localPreviewUrl,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
          )
              : Image.file(
            File(attachment.localPreviewUrl),
            width: _size,
            height: _size,
            fit: BoxFit.cover,
          ),
        ),
        // ×-remove button
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => onRemove(index),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 4)
                ],
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ── + Add image button ────────────────────────────────────────────────────────

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({
    required this.onPickGallery,
    required this.onPickCamera,
  });

  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: c.primary.withValues(alpha: 0.4),
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 26, color: c.primary),
            const SizedBox(height: 4),
            Text(
              'add_image'.tr,
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.primary),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library_outlined, color: c.primary),
              ),
              title: Text('pick_from_gallery'.tr,
                  style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark)),
              onTap: () {
                Navigator.pop(context);
                onPickGallery();
              },
            ),
            // Hide camera on web — not supported
            if (!kIsWeb)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.accentTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.camera_alt_outlined, color: c.accent),
                ),
                title: Text('take_photo'.tr,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontWeight: FontWeight.w600,
                        color: c.textDark)),
                onTap: () {
                  Navigator.pop(context);
                  onPickCamera();
                },
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Compact strip (inside reply bar) ─────────────────────────────────────────

class _CompactAttachmentStrip extends StatelessWidget {
  const _CompactAttachmentStrip({
    required this.attachments,
    required this.canAdd,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemove,
  });

  final List<PendingAttachment> attachments;
  final bool canAdd;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final ValueChanged<int> onRemove;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (attachments.isEmpty && !canAdd) return const SizedBox.shrink();

    return SizedBox(
      height: _size + 12,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [
          ...attachments.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: kIsWeb
                    ? Image.network(e.value.localPreviewUrl,
                    width: _size, height: _size, fit: BoxFit.cover)
                    : Image.file(File(e.value.localPreviewUrl),
                    width: _size, height: _size, fit: BoxFit.cover),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () => onRemove(e.key),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 10, color: Colors.white),
                  ),
                ),
              ),
            ]),
          )),
          if (canAdd)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: () => _AddImageButton(
                  onPickGallery: onPickGallery,
                  onPickCamera: onPickCamera,
                )._showPicker(context),
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: c.primary.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: Icon(Icons.add_photo_alternate_outlined,
                      size: 20, color: c.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Tab 1 — Complaints History
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
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.complaints.isEmpty) {
      return _EmptyHistory();
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadComplaints(reset: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: provider.complaints.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final complaint   = provider.complaints[i];
          final isExpanded  = expandedIds.contains(complaint.id);
          final isLoaded    = loadedIds.contains(complaint.id);
          final fullComplaint = isLoaded
              ? provider.complaints.firstWhere(
                (c) => c.id == complaint.id,
            orElse: () => complaint,
          )
              : complaint;

          return _ComplaintHistoryCard(
            complaint: fullComplaint,
            isExpanded: isExpanded,
            isLoading: isExpanded && !isLoaded,
            onToggle: () => onToggle(complaint.id),
          );
        },
      ),
    );
  }
}

// ── Single expandable complaint card ─────────────────────────────────────────

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
    final c         = context.colors;
    final statusClr = _statusColor(complaint.status);
    final hasUnread = !complaint.isReadByUser;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
        border: hasUnread && !isExpanded
            ? Border.all(color: c.primary.withValues(alpha: 0.45), width: 1.5)
            : isExpanded
            ? Border.all(
            color: statusClr.withValues(alpha: 0.4), width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 4,
                  height: 42,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: _priorityColor(complaint.priority),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            margin: const EdgeInsets.only(right: 6),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: c.primary, shape: BoxShape.circle),
                          ),
                        _StatusBadge(
                          label: _statusLabel(complaint.status),
                          color: statusClr,
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        _CategoryBadge(
                          label: _categoryLabel(complaint.category),
                          primary: c.primary,
                          tint: c.primaryTint,
                        ),
                        const Spacer(),
                        _RepliesCountChip(count: complaint.repliesCount, c: c),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: c.textLight),
                ),
              ]),
            ),
          ),

          // ── Expanded body ────────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: isLoading
                ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
                : _ExpandedBody(complaint: complaint),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open       => const Color(0xFFF59E0B),
    ComplaintStatus.inProgress => const Color(0xFF3B82F6),
    ComplaintStatus.resolved   => const Color(0xFF10B981),
    ComplaintStatus.closed     => const Color(0xFF6B7280),
  };

  Color _priorityColor(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => const Color(0xFFEF4444),
    ComplaintPriority.high   => const Color(0xFFF97316),
    ComplaintPriority.medium => const Color(0xFFF59E0B),
    ComplaintPriority.low    => const Color(0xFF10B981),
  };

  String _statusLabel(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open       => 'status_open'.tr,
    ComplaintStatus.inProgress => 'status_in_progress'.tr,
    ComplaintStatus.resolved   => 'status_resolved'.tr,
    ComplaintStatus.closed     => 'status_closed'.tr,
  };

  String _categoryLabel(ComplaintCategory cat) => switch (cat) {
    ComplaintCategory.technical    => 'category_technical'.tr,
    ComplaintCategory.payment      => 'category_payment'.tr,
    ComplaintCategory.courseContent => 'category_content'.tr,
    ComplaintCategory.teacher      => 'category_teacher'.tr,
    ComplaintCategory.student      => 'category_student'.tr,
    ComplaintCategory.general      => 'category_general'.tr,
  };
}

// ── Expanded complaint body with description + attachments + replies ──────────

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.complaint});
  final ComplaintModel complaint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: c.divider, height: 1),
        const SizedBox(height: 12),

        // Description
        Text(complaint.description, style: c.body.copyWith(height: 1.7)),

        // Attachments on the complaint itself
        if (complaint.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AttachmentGallery(attachments: complaint.attachments),
        ],

        // Resolved at tag
        if (complaint.resolvedAt != null) ...[
          const SizedBox(height: 12),
          _ResolvedBanner(resolvedAt: complaint.resolvedAt!),
        ],

        // Replies
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

// ── Attachment image gallery ──────────────────────────────────────────────────

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
            fontFamily: 'bahji',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textLight),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: attachments.map((a) => _NetworkThumb(url: a.fileUrl)).toList(),
      ),
    ]);
  }
}

class _NetworkThumb extends StatelessWidget {
  const _NetworkThumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
            Icon(Icons.broken_image_outlined, color: context.colors.textLight),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenImage(url: url),
        fullscreenDialog: true,
      ),
    );
  }
}

class _FullscreenImage extends StatelessWidget {
  const _FullscreenImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ── Mini reply bubble (used inside the expandable history card) ────────────────

class _HistoryReplyBubble extends StatelessWidget {
  const _HistoryReplyBubble({required this.reply});
  final ComplaintReply reply;

  @override
  Widget build(BuildContext context) {
    final c       = context.colors;
    final isAdmin = reply.isAdmin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
        isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: c.primary.withValues(alpha: 0.15),
              backgroundImage: reply.senderImage != null
                  ? NetworkImage(reply.senderImage!)
                  : null,
              child: reply.senderImage == null
                  ? Icon(Icons.support_agent_rounded,
                  size: 14, color: c.primary)
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAdmin ? c.primaryTint : c.primary,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(14),
                  topRight:    const Radius.circular(14),
                  bottomLeft:  Radius.circular(isAdmin ? 4 : 14),
                  bottomRight: Radius.circular(isAdmin ? 14 : 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        reply.senderName,
                        style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c.accent),
                      ),
                    ),
                  Text(
                    reply.message,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 13,
                        color: isAdmin ? c.textDark : Colors.white),
                  ),
                  // Reply attachments
                  if (reply.attachments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reply.attachments
                          .map((a) => _NetworkThumb(url: a.fileUrl))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Resolved banner ───────────────────────────────────────────────────────────

class _ResolvedBanner extends StatelessWidget {
  const _ResolvedBanner({required this.resolvedAt});
  final DateTime resolvedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_outline_rounded, size: 16, color: c.success),
        const SizedBox(width: 8),
        Text(
          '${'resolved_at_prefix'.tr} ${_fmt(resolvedAt)}',
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 12,
              color: c.success,
              fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: c.primaryShadow,
          ),
          child: const Icon(Icons.inbox_outlined, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 18),
        Text('no_previous_complaints'.tr, style: c.h2.copyWith(fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          'complaints_appear_after_send'.tr,
          style: c.caption.copyWith(color: c.textLight),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared pickers & badges
// ══════════════════════════════════════════════════════════════════════════════

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.colors.h3.copyWith(fontSize: 14));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color)),
  );
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge(
      {required this.label, required this.primary, required this.tint});
  final String label;
  final Color primary;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: primary)),
  );
}

class _RepliesCountChip extends StatelessWidget {
  const _RepliesCountChip({required this.count, required this.c});
  final int count;
  final AppColors c;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.chat_bubble_outline_rounded, size: 13, color: c.textLight),
      const SizedBox(width: 3),
      Text('$count', style: c.caption.copyWith(fontSize: 11)),
    ],
  );
}

// ── Category picker ───────────────────────────────────────────────────────────

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});
  final ComplaintCategory selected;
  final ValueChanged<ComplaintCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = {
      ComplaintCategory.general:       ('category_general'.tr,  Icons.help_outline_rounded),
      ComplaintCategory.technical:     ('category_technical'.tr, Icons.bug_report_outlined),
      ComplaintCategory.payment:       ('category_payment'.tr,  Icons.payment_outlined),
      ComplaintCategory.courseContent: ('category_content'.tr,  Icons.book_outlined),
      ComplaintCategory.teacher:       ('category_teacher'.tr,  Icons.person_outline_rounded),
      ComplaintCategory.student:       ('category_student'.tr,  Icons.school_outlined),
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ComplaintCategory.values.map((cat) {
        final (label, icon) = labels[cat]!;
        final sel = selected == cat;
        return GestureDetector(
          onTap: () => onChanged(cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? c.primary : c.cardBg,
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: sel ? c.primary : c.divider, width: 1.5),
              boxShadow: sel ? c.primaryShadow : c.cardShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: sel ? Colors.white : c.textLight),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : c.textMedium)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ── Priority picker ───────────────────────────────────────────────────────────

class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker({required this.selected, required this.onChanged});
  final ComplaintPriority selected;
  final ValueChanged<ComplaintPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = {
      ComplaintPriority.low:    ('priority_low'.tr,    const Color(0xFF10B981)),
      ComplaintPriority.medium: ('priority_medium'.tr, const Color(0xFFF59E0B)),
      ComplaintPriority.high:   ('priority_high'.tr,   const Color(0xFFF97316)),
      ComplaintPriority.urgent: ('priority_urgent'.tr, const Color(0xFFEF4444)),
    };
    return Row(
      children: ComplaintPriority.values.map((p) {
        final (label, color) = meta[p]!;
        final sel = selected == p;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? color : c.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? color : c.divider, width: 1.5),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : color),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}