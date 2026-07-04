// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaints_screen.dart
// Works for both Student and Teacher roles — role-aware display.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../auth/auth_provider.dart';
import '../../../auth/auth_widgets.dart';
import 'complaint_model.dart';
import 'complaint_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ComplaintProvider>();
      p.loadComplaints(reset: true);
      p.loadStats();
    });
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !context.read<ComplaintProvider>().isLoadingList) {
      context.read<ComplaintProvider>().loadComplaints();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ComplaintProvider>();
    final auth = context.watch<AuthProvider>();
    log(' persona is ${auth.isStudent}');
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'complaints_and_support'.tr),
            _StatsBanner(stats: p.stats),
            _FilterRow(provider: p, searchCtrl: _searchCtrl),
            Expanded(
              child: p.isLoadingList && p.complaints.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : p.complaints.isEmpty
                  ? _EmptyState()
                  : RefreshIndicator(
                      onRefresh: () => p.loadComplaints(reset: true),
                      child: ListView.separated(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount:
                            p.complaints.length + (p.isLoadingList ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          if (i >= p.complaints.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return _ComplaintCard(
                            complaint: p.complaints[i],
                            isAdmin: !auth.isStudent,
                            onTap: () => _openDetail(p.complaints[i].id),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<ComplaintProvider>(),
          child: ComplaintDetailScreen(complaintId: id),
        ),
      ),
    );
  }
}

// ── Stats Banner ──────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.stats});

  final ComplaintStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.primaryShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'stat_all'.tr, value: stats.total, color: Colors.white),
          _vDivider,
          _Stat(
            label: 'status_open'.tr,
            value: stats.open,
            color: const Color(0xFFFFF0B3),
          ),
          _vDivider,
          _Stat(
            label: 'status_in_progress'.tr,
            value: stats.inProgress,
            color: const Color(0xFFB3E5FC),
          ),
          _vDivider,
          _Stat(
            label: 'status_resolved_banner'.tr,
            value: stats.resolved,
            color: const Color(0xFFB9F6CA),
          ),
        ],
      ),
    );
  }

  Widget get _vDivider => Container(
    width: 1,
    height: 32,
    color: Colors.white.withValues(alpha: 0.3),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'bahji',
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}

// ── Filter Row ────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.provider, required this.searchCtrl});

  final ComplaintProvider provider;
  final TextEditingController searchCtrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTextField(
            controller: searchCtrl,
            label: 'search_complaints_hint'.tr,
            icon: Icons.search_rounded,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'stat_all'.tr,
                  selected: provider.statusFilter == null,
                  onTap: () => provider.setStatusFilter(null),
                ),
                ...ComplaintStatus.values.map(
                  (s) => _FilterChip(
                    label: _statusLabel(s),
                    selected: provider.statusFilter == s,
                    color: _statusColor(s),
                    onTap: () => provider.setStatusFilter(s),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => 'status_open'.tr,
    ComplaintStatus.inProgress => 'status_in_progress'.tr,
    ComplaintStatus.resolved => 'status_resolved'.tr,
    ComplaintStatus.closed => 'status_closed'.tr,
  };

  Color _statusColor(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => const Color(0xFFF59E0B),
    ComplaintStatus.inProgress => const Color(0xFF3B82F6),
    ComplaintStatus.resolved => const Color(0xFF10B981),
    ComplaintStatus.closed => const Color(0xFF6B7280),
  };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? c.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : c.divider, width: 1.5),
          boxShadow: selected ? c.cardShadow : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : c.textMedium,
          ),
        ),
      ),
    );
  }
}

// ── Complaint Card ────────────────────────────────────────────────────────────

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.isAdmin,
    required this.onTap,
  });

  final ComplaintModel complaint;
  final bool isAdmin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusClr = _statusColor(complaint.status);
    final hasUnread = isAdmin
        ? !complaint.isReadByAdmin
        : !complaint.isReadByUser;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(c.radiusMedium),
          boxShadow: c.cardShadow,
          border: hasUnread
              ? Border.all(color: c.primary.withValues(alpha: 0.5), width: 1.5)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: _priorityColor(complaint.priority),
                      shape: BoxShape.circle,
                    ),
                  ),
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
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                complaint.description,
                style: c.caption.copyWith(height: 1.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusClr.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(complaint.status),
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusClr,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _categoryLabel(complaint.category),
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Attachment indicator
                  if (complaint.attachments.isNotEmpty) ...[
                    Icon(
                      Icons.photo_library_outlined,
                      size: 14,
                      color: c.textLight,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${complaint.attachments.length}',
                      style: c.caption.copyWith(fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Suggestion indicator
                  if (complaint.suggestedSolution != null) ...[
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 14,
                      color: Color(0xFF059669),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: c.textLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${complaint.repliesCount}',
                        style: c.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDate(complaint.updatedAt),
                    style: c.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => const Color(0xFFF59E0B),
    ComplaintStatus.inProgress => const Color(0xFF3B82F6),
    ComplaintStatus.resolved => const Color(0xFF10B981),
    ComplaintStatus.closed => const Color(0xFF6B7280),
  };

  Color _priorityColor(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => const Color(0xFFEF4444),
    ComplaintPriority.high => const Color(0xFFF97316),
    ComplaintPriority.medium => const Color(0xFFF59E0B),
    ComplaintPriority.low => const Color(0xFF10B981),
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

  String _formatDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60)
      return 'ago_minutes_short'.tr.replaceAll('{n}', '${diff.inMinutes}');
    if (diff.inHours < 24)
      return 'ago_hours_short'.tr.replaceAll('{n}', '${diff.inHours}');
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: c.primaryShadow,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Text('no_complaints_yet'.tr, style: c.h2.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'complaints_empty_hint'.tr,
            style: c.caption.copyWith(color: c.textLight),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Complaint Detail Screen
// ══════════════════════════════════════════════════════════════════════════════

class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final int complaintId;

  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComplaintProvider>().loadDetail(widget.complaintId);
    });
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    // Clear any staged reply images if user navigates away
    // context.read<ComplaintProvider>().clearReplyImages();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    final p = context.read<ComplaintProvider>();
    if (msg.isEmpty && p.pendingReplyAttachments.isEmpty) return;
    _replyCtrl.clear();

    await p.addReply(complaintId: widget.complaintId, message: msg);
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ComplaintProvider>();
    final c = context.colors;
    final auth = context.read<AuthProvider>();
    final complaint = p.selected;
    log(' persona is===========> ${auth.isStudent}');
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'complaint_details_title'.tr),
              if (p.isLoadingDetail)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (complaint == null)
                Expanded(child: Center(child: Text('complaint_not_found'.tr)))
              else ...[
                Expanded(
                  child: ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      // ── Info card ──────────────────────────────────────────
                      _InfoCard(
                        complaint: complaint,
                        isAdmin: !auth.isStudent,
                        provider: p,
                      ),
                      const SizedBox(height: 16),
                      // ── Replies ────────────────────────────────────────────
                      if (complaint.replies.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text('replies_label'.tr, style: c.h3),
                        ),
                        ...complaint.replies.map(
                          (r) => _ReplyBubble(
                            reply: r,
                            myId: auth.currentUser?.id ?? 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                // ── Reply input ──────────────────────────────────────────────
                if (complaint.status != ComplaintStatus.closed)
                  _ReplyInput(
                    controller: _replyCtrl,
                    isSending: p.isSending,
                    pendingAttachments: p.pendingReplyAttachments,
                    onSend: _sendReply,
                    onPickGallery: () => p.pickReplyImage(),
                    onPickCamera: () => p.pickReplyImageFromCamera(),
                    onRemoveImage: (i) => p.removeReplyImage(i),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.complaint,
    required this.isAdmin,
    required this.provider,
  });

  final ComplaintModel complaint;
  final bool isAdmin;
  final ComplaintProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusClr = _statusColor(complaint.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status
          Row(
            children: [
              Expanded(
                child: Text(
                  complaint.title,
                  style: c.h2.copyWith(fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusClr.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(complaint.status),
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusClr,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Meta
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.label_outline_rounded,
                label: _categoryLabel(complaint.category),
                color: c.primary,
              ),
              _MetaChip(
                icon: Icons.flag_outlined,
                label: _priorityLabel(complaint.priority),
                color: _priorityColor(complaint.priority),
              ),
              if (complaint.courseTitle != null)
                _MetaChip(
                  icon: Icons.book_outlined,
                  label: complaint.courseTitle!,
                  color: c.accent,
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Description
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              complaint.description,
              style: c.body.copyWith(height: 1.7),
            ),
          ),

          // ── Suggested solution ───────────────────────────────────────────
          if (complaint.suggestedSolution != null) ...[
            const SizedBox(height: 14),
            _SuggestedSolutionBlock(text: complaint.suggestedSolution!),
          ],

          // ── Complaint-level attachments ──────────────────────────────────
          if (complaint.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'attachments_label'.tr,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textMedium,
              ),
            ),
            const SizedBox(height: 10),
            _AttachmentGallery(attachments: complaint.attachments),
          ],

          // Admin status updater
          if (isAdmin) ...[
            const SizedBox(height: 16),
            Text('update_status_label'.tr, style: c.caption),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ComplaintStatus.values.map((s) {
                final selected = complaint.status == s;
                final sc = _statusColor(s);
                return GestureDetector(
                  onTap: selected
                      ? null
                      : () => provider.updateStatus(complaint.id, s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? sc : c.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sc, width: 1.5),
                    ),
                    child: Text(
                      _statusLabel(s),
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : sc,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(ComplaintStatus s) => switch (s) {
    ComplaintStatus.open => const Color(0xFFF59E0B),
    ComplaintStatus.inProgress => const Color(0xFF3B82F6),
    ComplaintStatus.resolved => const Color(0xFF10B981),
    ComplaintStatus.closed => const Color(0xFF6B7280),
  };

  Color _priorityColor(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => const Color(0xFFEF4444),
    ComplaintPriority.high => const Color(0xFFF97316),
    ComplaintPriority.medium => const Color(0xFFF59E0B),
    ComplaintPriority.low => const Color(0xFF10B981),
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

  String _priorityLabel(ComplaintPriority p) => switch (p) {
    ComplaintPriority.urgent => 'priority_urgent'.tr,
    ComplaintPriority.high => 'priority_high'.tr,
    ComplaintPriority.medium => 'priority_medium'.tr,
    ComplaintPriority.low => 'priority_low'.tr,
  };
}

// ── Attachment gallery (from server) ─────────────────────────────────────────

class _AttachmentGallery extends StatelessWidget {
  const _AttachmentGallery({required this.attachments});

  final List<ComplaintAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (a) =>
                _NetworkThumb(url: a.fileUrl, objectId: '${a.id}-attachment'),
          )
          .toList(),
    );
  }
}

class _NetworkThumb extends StatelessWidget {
  const _NetworkThumb({required this.url, required this.objectId});

  final String url;
  final Object objectId;
  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    return AppNetworkImage(
      url: url,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      heroTag: objectId,
    );
  }
}
// ── Meta Chip ─────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reply Bubble ──────────────────────────────────────────────────────────────

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply, required this.myId});

  final ComplaintReply reply;
  final int myId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMe = reply.senderId == myId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: reply.isAdmin
                  ? c.primary.withValues(alpha: 0.15)
                  : c.accent.withValues(alpha: 0.15),
              backgroundImage: reply.senderImage != null
                  ? NetworkImage(reply.senderImage!)
                  : null,
              child: reply.senderImage == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: reply.isAdmin ? c.primary : c.accent,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? c.primary
                    : reply.isAdmin
                    ? c.accentTint
                    : c.cardBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: c.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        reply.senderName,
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: reply.isAdmin ? c.accent : c.textMedium,
                        ),
                      ),
                    ),
                  if (reply.message.isNotEmpty)
                    Text(
                      reply.message,
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 14,
                        height: 1.5,
                        color: isMe ? Colors.white : c.textDark,
                      ),
                    ),

                  // ── Reply image attachments ──────────────────────────────
                  if (reply.attachments.isNotEmpty) ...[
                    if (reply.message.isNotEmpty) const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reply.attachments
                          .map(
                            (a) => _NetworkThumb(
                              url: a.fileUrl,
                              objectId: '${a.id}-replay',
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 4),
                  Text(
                    _formatTime(reply.createdAt),
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 10,
                      color: isMe ? Colors.white60 : c.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Reply Input (with image attach strip) ─────────────────────────────────────

class _ReplyInput extends StatelessWidget {
  const _ReplyInput({
    required this.controller,
    required this.isSending,
    required this.pendingAttachments,
    required this.onSend,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemoveImage,
  });

  final TextEditingController controller;
  final bool isSending;
  final List<PendingAttachment> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Pending image strip ────────────────────────────────────────────
          if (pendingAttachments.isNotEmpty)
            _PendingImageStrip(
              attachments: pendingAttachments,
              onRemove: onRemoveImage,
            ),

          // ── Text input row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                // Camera / gallery button
                GestureDetector(
                  onTap: () => _showImagePicker(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 20,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: c.divider),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: 'bahji', color: c.textDark),
                      decoration: InputDecoration(
                        hintText: 'write_reply_hint'.tr,
                        hintStyle: TextStyle(
                          fontFamily: 'bahji',
                          color: c.textLight,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Send button
                GestureDetector(
                  onTap: isSending ? null : onSend,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: c.primaryShadow,
                    ),
                    child: isSending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
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

  void _showImagePicker(BuildContext context) {
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
                  onPickGallery();
                },
              ),
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
                    onPickCamera();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending image strip inside reply bar ──────────────────────────────────────

class _PendingImageStrip extends StatelessWidget {
  const _PendingImageStrip({required this.attachments, required this.onRemove});

  final List<PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: _size + 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? AppNetworkImage(
                      url: attachments[i].localPreviewUrl,
                      heroTag:
                          '${attachments[i].localPreviewUrl}-Pending',
                      width: _size,
                      height: _size,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      File(attachments[i].localPreviewUrl),
                      width: _size,
                      height: _size,
                      fit: BoxFit.cover,
                    ),
            ),
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: () => onRemove(i),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suggested solution display block (read-only) ──────────────────────────────
// Used in both _InfoCard (detail screen) and _ExpandedBody (history card).

class _SuggestedSolutionBlock extends StatelessWidget {
  const _SuggestedSolutionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const Color accent = Color(0xFF059669); // emerald-600
    const Color tint = Color(0xFFD1FAE5); // emerald-100
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                'suggested_solution_label'.tr,
                style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'by_student'.tr,
                  style: const TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: c.body.copyWith(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
