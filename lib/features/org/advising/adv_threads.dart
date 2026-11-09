// lib/features/org/advising/adv_threads.dart — advising conversations (docs/advising/PHASE5.md "Threads"): the list
// (one filter: status · overdue · complaints), the thread (messages with attachments, a composer with offline drafts
// and a `client_id`, templates for staff, Close / Reopen and Escalate with confirmation) and the new conversation
// sheet (a student: a message or a complaint, "About my advisor" explained; staff: a message to one student).
//
//   AdvThreadCard · AdvThreadsView · AdvMessageBubble · AdvThreadView · AdvNewThreadForm   plain values
//   AdvThreadsPage · AdvThreadPage · showAdvNewThreadSheet                                 load / write
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart';
import '../org_providers.dart' show OrgSession;
import '../org_ui.dart' show orgNameOf;
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvPriorityPill, AdvTypedField, AdvTypedText;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_draft_store.dart' show AdvSendState;
import 'adv_message_store.dart';
import 'adv_models.dart' show advPriorityLabel;
import 'adv_parts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The list (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvThreadCard extends StatelessWidget {
  const AdvThreadCard({super.key, required this.thread, this.staff = true, this.showStudent = true, this.onTap});
  final AdvThread thread;
  final bool staff, showStudent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = thread;
    final unread = x.unread > 0;
    final when = x.lastMessageAt ?? x.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 20,
                backgroundColor: (x.kind == 'complaint' ? c.warning : c.primary).withValues(alpha: c.isDark ? 0.22 : 0.12),
                child: Icon(x.kind == 'complaint' ? Icons.report_outlined : Icons.forum_outlined, size: AppIconSize.md, color: appInk(context, x.kind == 'complaint' ? c.warning : c.primary)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(x.subjectShown,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: advTextDirection(x.subjectShown),
                        style: AppType.row(context).copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  if (when != null) ...[
                    const SizedBox(width: AppSpace.xs),
                    Text(relTime(when.toLocal()), style: AppType.meta(context)),
                  ],
                ]),
                if (staff && showStudent) Text(x.studentShown, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark)),
                if (x.preview.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  AdvTypedText(x.preview, maxLines: 2, style: AppType.meta(context).copyWith(color: unread ? c.textDark : null)),
                ],
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AdvThreadStatusPill(status: x.status, overdue: x.overdue, staff: staff),
                  if (x.kind == 'complaint') AppBadgePill(x.kindLabel, color: c.warning, icon: Icons.report_outlined),
                  if (x.priority != 'normal') AdvPriorityPill(priority: x.priority),
                  if (x.escalated) AppBadgePill(t('معاملة #${x.workItemId}', 'Work item #${x.workItemId}'), color: c.danger, icon: Icons.account_tree_outlined),
                  AdvCountDot(count: x.unread),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class AdvThreadsView extends StatelessWidget {
  const AdvThreadsView({
    super.key,
    required this.load,
    required this.query,
    this.threads = const [],
    this.unreadTotal = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.staff = true,
    this.showStudent = true,
    this.errorText,
    this.onRetry,
    this.onSearch,
    this.onFilter,
    this.onOpen,
    this.onNew,
    this.onMore,
  });

  final AdvLoad load;
  final AdvThreadQuery query;
  final List<AdvThread> threads;
  final int unreadTotal;
  final bool hasMore, loadingMore, staff, showStudent;
  final String? errorText;
  final VoidCallback? onRetry, onNew, onMore;
  final ValueChanged<String>? onSearch, onFilter;
  final ValueChanged<AdvThread>? onOpen;

  @override
  Widget build(BuildContext context) {
    final filtered = query.filter.isNotEmpty || query.q.trim().isNotEmpty;
    Widget body;
    if (load != AdvLoad.ready) {
      body = AdvLoadState(state: load, errorText: errorText, onRetry: onRetry);
    } else if (threads.isEmpty) {
      body = filtered
          ? AppEmpty(
              icon: Icons.filter_alt_off_rounded,
              title: t('لا محادثات تطابق', 'No conversations match'),
              message: t('جرّب تصفية أخرى.', 'Try another filter.'),
              actionLabel: onFilter == null ? null : t('كل المحادثات', 'All conversations'),
              onAction: onFilter == null ? null : () => onFilter!(''),
            )
          : AppEmpty(
              icon: Icons.forum_outlined,
              title: t('لا محادثات بعد', 'No conversations yet'),
              message: staff
                  ? t('تظهر هنا رسائل طلابك وشكاواهم، ويمكنك مراسلة طالب من ملفه.', 'Your students\' messages and complaints show here; message a student from their record.')
                  : t('اكتب لمرشدك سؤالاً أو طلباً، وتصلك الإجابة هنا.', 'Ask your advisor a question or a request; the answer comes here.'),
              actionLabel: onNew == null ? null : t('رسالة جديدة', 'New message'),
              onAction: onNew,
            );
    } else {
      body = AdvPageFrame(fab: onNew != null, maxWidth: 1440, children: [
        if (unreadTotal > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(
              countText(unreadTotal, ar1: 'رسالة واحدة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '$unreadTotal رسائل غير مقروءة', arMany: '$unreadTotal رسالة غير مقروءة', en1: '1 unread message', en: '$unreadTotal unread messages'),
              style: AppType.meta(context),
            ),
          ),
        for (final x in threads) AdvThreadCard(thread: x, staff: staff, showStudent: showStudent, onTap: onOpen == null ? null : () => onOpen!(x)),
        if (hasMore && onMore != null)
          Align(
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: loadingMore ? null : onMore,
              icon: loadingMore ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_more_rounded),
              label: Text(t('محادثات أقدم', 'Older conversations')),
            ),
          ),
      ]);
    }
    return OrgPageBody(
      primary: onNew == null ? null : OrgPrimaryAction(icon: Icons.edit_outlined, label: t('رسالة جديدة', 'New message'), onTap: onNew!),
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث في العناوين', 'Search the subjects'), onChanged: onSearch!),
      filter: onFilter == null
          ? null
          : OrgFilterButton<String>(value: query.filter, defaultValue: '', options: advThreadFilters(staff: staff), label: t('الحالة', 'Status'), onChanged: onFilter!),
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The list page
// ═════════════════════════════════════════════════════════════════════════════

class AdvThreadsPage extends StatelessWidget {
  const AdvThreadsPage({super.key, required this.orgId, this.student = false, this.memberId, this.studentName, this.advisors = const []});
  final int orgId;
  final bool student;

  /// Staff: one student's conversations (and "New message" to them).
  final int? memberId;
  final String? studentName;

  /// A student: their advisors (user id, name), for a complaint about one of them.
  final List<(int, String)> advisors;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: student ? t('رسائلي مع المرشد', 'Messages with my advisor') : t('رسائل الإرشاد', 'Advising messages'),
        subtitle: studentName,
        maxWidth: 1440,
        child: _AdvThreadsBody(orgId: orgId, student: student, memberId: memberId, studentName: studentName, advisors: advisors),
      );
}

class _AdvThreadsBody extends StatefulWidget {
  const _AdvThreadsBody({required this.orgId, required this.student, this.memberId, this.studentName, this.advisors = const []});
  final int orgId;
  final bool student;
  final int? memberId;
  final String? studentName;
  final List<(int, String)> advisors;

  @override
  State<_AdvThreadsBody> createState() => _AdvThreadsBodyState();
}

class _AdvThreadsBodyState extends State<_AdvThreadsBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId, student: widget.student);
  OrgPageRefresh? _refresh;
  StreamSubscription<LiveEvent>? _live;
  late AdvThreadQuery _query = AdvThreadQuery(memberId: widget.memberId);
  final List<AdvThread> _items = [];
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  int _unread = 0, _page = 1, _pages = 1, _req = 0;
  bool _loadingMore = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _live = LiveEvents.instance.listen({LiveEvents.connectivity}, (_) {
      if (mounted && AppConnectivity.instance.isOnline && _load != AdvLoad.ready) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() => _fetch();

  Future<void> _fetch({bool more = false}) async {
    final req = ++_req;
    final q = _query.copyWith(page: more ? _page + 1 : 1);
    if (more) setState(() => _loadingMore = true);
    final r = await orgCall(() => _api.threads(q), quiet: true);
    if (!mounted || req != _req) return;
    setState(() {
      _loadingMore = false;
      if (r.ok) {
        final l = r.data as AdvThreadList;
        if (!more) _items.clear();
        _items.addAll([for (final x in l.page.items) if (!_items.any((y) => y.id == x.id)) x]);
        _page = l.page.page;
        _pages = l.page.pages;
        _unread = l.unreadTotal;
        _load = AdvLoad.ready;
      } else if (!more) {
        _load = advFailLoad(r);
        _error = advCommErrorText(r.error!);
      } else {
        showAppNotice(advCommErrorText(r.error!), error: true);
      }
    });
    if (r.ok && !more && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _set(AdvThreadQuery q) {
    setState(() {
      _query = q;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<void> _open(AdvThread x) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvThreadPage(orgId: widget.orgId, threadId: x.id, student: widget.student, subject: x.subjectShown)));
    if (mounted) _reload();
  }

  Future<void> _new() async {
    final made = await showAdvNewThreadSheet(context, _api, memberId: widget.memberId, studentName: widget.studentName, advisors: widget.advisors);
    if (made == null || !mounted) return;
    _reload();
    _open(made);
  }

  @override
  Widget build(BuildContext context) => AdvThreadsView(
        load: _load,
        query: _query,
        threads: _items,
        unreadTotal: _unread,
        hasMore: _page < _pages,
        loadingMore: _loadingMore,
        staff: !widget.student,
        showStudent: widget.memberId == null,
        errorText: _error,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onSearch: widget.student
            ? null
            : (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => _set(_query.copyWith(q: q, page: 1)));
              },
        onFilter: (f) => _set(_query.withFilter(f)),
        onOpen: _open,
        onNew: widget.student || widget.memberId != null ? _new : null,
        onMore: () => _fetch(more: true),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The thread (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvMessageBubble extends StatelessWidget {
  const AdvMessageBubble({super.key, required this.message, this.onOpenAttachment, this.pending = false});
  final AdvMessage message;
  final ValueChanged<AdvAttachment>? onOpenAttachment;

  /// Written offline, waiting to be sent.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    final mine = m.mine || pending;
    final tint = mine ? c.primary.withValues(alpha: c.isDark ? 0.24 : 0.10) : c.cardBg;
    final meta = [
      if (!mine && m.senderName.isNotEmpty) m.senderName,
      if (pending) t('بانتظار الاتصال', 'Waiting for a connection') else if (m.createdAt != null) AppTime.dateTime(m.createdAt!),
    ].join(' · ');
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86 > 620 ? 620 : MediaQuery.sizeOf(context).width * 0.86),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(AppRadius.card),
              topEnd: const Radius.circular(AppRadius.card),
              bottomStart: Radius.circular(mine ? AppRadius.card : AppSpace.xxs),
              bottomEnd: Radius.circular(mine ? AppSpace.xxs : AppRadius.card),
            ),
            border: Border.all(color: mine ? c.primary.withValues(alpha: 0.25) : c.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (meta.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (pending) ...[Icon(Icons.schedule_rounded, size: AppIconSize.xs, color: appInk(context, c.warning)), const SizedBox(width: AppSpace.xxs)],
                Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
              ]),
            const SizedBox(height: AppSpace.xxs),
            SelectionArea(child: AdvTypedText(m.body)),
            if (m.attachments.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final a in m.attachments) AdvAttachmentChip(attachment: a, onOpen: onOpenAttachment == null ? null : () => onOpenAttachment!(a)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The thread's head: subject, kind, status, priority, the reply-by time, the work item it was escalated to.
class AdvThreadHeader extends StatelessWidget {
  const AdvThreadHeader({super.key, required this.thread, this.staff = true});
  final AdvThread thread;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = thread;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(x.subjectShown, textDirection: advTextDirection(x.subjectShown), style: AppType.section(context))),
        if (staff) Text(x.studentShown, style: AppType.meta(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          AdvThreadStatusPill(status: x.status, overdue: x.overdue, staff: staff),
          AppBadgePill(x.kindLabel, color: x.kind == 'complaint' ? c.warning : c.primary, icon: x.kind == 'complaint' ? Icons.report_outlined : Icons.forum_outlined),
          if (x.priority != 'normal') AdvPriorityPill(priority: x.priority),
        ]),
        if (staff && x.slaDueAt != null && !x.closed)
          AdvInfoLine(
            icon: Icons.alarm_rounded,
            color: x.overdue ? c.danger : null,
            text: x.overdue ? t('تجاوز موعد الرد (${AppTime.dateTime(x.slaDueAt!)})', 'Past the reply time (${AppTime.dateTime(x.slaDueAt!)})') : t('الرد قبل ${AppTime.dateTime(x.slaDueAt!)}', 'Reply by ${AppTime.dateTime(x.slaDueAt!)}'),
          ),
        if (x.aboutAdvisor && staff)
          AdvInfoLine(icon: Icons.lock_outline_rounded, text: t('شكوى عن مرشد: يراها مديرو الإرشاد فقط ولا تظهر للمرشد المعني', 'A complaint about an advisor: only the advising directors see it, never that advisor')),
        if (x.aboutAdvisor && !staff)
          AdvInfoLine(icon: Icons.lock_outline_rounded, text: t('تصل إلى مدير الإرشاد ولا يراها مرشدك', 'It goes to the advising director; your advisor does not see it')),
        if (x.escalated)
          AdvInfoLine(
            icon: Icons.account_tree_outlined,
            color: c.danger,
            text: [t('صُعّدت إلى المعاملة #${x.workItemId}', 'Escalated to work item #${x.workItemId}'), if (advWorkItemStatusLabel(x.workItemStatus).isNotEmpty) advWorkItemStatusLabel(x.workItemStatus)].join(' · '),
          ),
      ]),
    );
  }
}

/// The reply composer: the text (its own direction), attachments, a template (staff), Send — or Save to send later.
class AdvMessageComposer extends StatelessWidget {
  const AdvMessageComposer({
    super.key,
    required this.body,
    this.attachments = const [],
    this.offline = false,
    this.draftSaved = false,
    this.uploading = false,
    this.busy = false,
    this.error,
    this.onAttach,
    this.onRemoveAttachment,
    this.onTemplate,
    this.onSend,
  });

  final TextEditingController body;
  final List<AdvAttachment> attachments;
  final bool offline, draftSaved, uploading, busy;
  final String? error;
  final VoidCallback? onAttach, onTemplate, onSend;
  final ValueChanged<AdvAttachment>? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (attachments.isNotEmpty) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in attachments) AdvAttachmentChip(attachment: a, onRemove: busy || onRemoveAttachment == null ? null : () => onRemoveAttachment!(a)),
        ]),
        const SizedBox(height: AppSpace.xs),
      ],
      AdvTypedField(controller: body, label: t('ردّك', 'Your reply'), minLines: 2, maxLines: 6, maxLength: advMessageMax, enabled: !busy),
      if (offline || draftSaved)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: AdvInfoLine(
            icon: offline ? Icons.wifi_off_rounded : Icons.save_outlined,
            color: offline ? c.warning : null,
            text: offline
                ? t('لا اتصال: تُحفظ الرسالة على هذا الجهاز وتُرسل عند عودة الاتصال', 'Offline: the message is kept on this device and sent when you are back online')
                : t('المسودة محفوظة على هذا الجهاز', 'Draft saved on this device'),
          ),
        ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.xs),
      LayoutBuilder(builder: (context, box) {
        final tools = [
          IconButton(
            tooltip: t('إرفاق ملف', 'Attach a file'),
            onPressed: busy || uploading || offline || onAttach == null || attachments.length >= advMaxAttachments ? null : onAttach,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            icon: uploading ? const SizedBox.square(dimension: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.attach_file_rounded),
          ),
          if (onTemplate != null)
            IconButton(
              tooltip: t('إدراج قالب', 'Insert a template'),
              onPressed: busy ? null : onTemplate,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: const Icon(Icons.description_outlined),
            ),
        ];
        // a narrow composer (a phone, a large text size): the tools on their own row, Send across the width
        final narrow = box.maxWidth < 440 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
        final send = ValueListenableBuilder<TextEditingValue>(
          valueListenable: body,
          builder: (context, v, _) => AppButton.primary(
            label: offline ? t('حفظ للإرسال لاحقاً', 'Save to send later') : t('إرسال', 'Send'),
            icon: offline ? Icons.save_alt_rounded : Icons.send_rounded,
            busy: busy,
            expand: narrow,
            onPressed: v.text.trim().isEmpty || uploading ? null : onSend,
          ),
        );
        if (!narrow) return Row(children: [...tools, const Spacer(), send]);
        return Row(children: [...tools, const SizedBox(width: AppSpace.xs), Expanded(child: send)]);
      }),
    ]);
  }
}

class AdvThreadView extends StatelessWidget {
  const AdvThreadView({
    super.key,
    required this.load,
    this.thread,
    this.messages = const [],
    this.queued = const [],
    this.composer,
    this.staff = true,
    this.hasOlder = false,
    this.loadingOlder = false,
    this.errorText,
    this.onRetry,
    this.onOlder,
    this.onOpenAttachment,
    this.onReopen,
    this.onDiscardQueued,
    this.onReopenQueued,
    this.scroll,
  });

  final AdvLoad load;
  final AdvThread? thread;
  final List<AdvMessage> messages;
  final List<AdvQueuedMessage> queued;

  /// null: closed (the reopen bar shows instead) or nothing to write.
  final Widget? composer;
  final bool staff, hasOlder, loadingOlder;
  final String? errorText;
  final VoidCallback? onRetry, onOlder, onReopen;
  final ValueChanged<AdvAttachment>? onOpenAttachment;
  final ValueChanged<AdvQueuedMessage>? onDiscardQueued, onReopenQueued;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final x = thread;
    if (load != AdvLoad.ready || x == null) return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    final c = context.colors;
    final waiting = [for (final q in queued) if (!q.failed) q];
    final refused = [for (final q in queued) if (q.failed) q];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md), children: [
              AdvThreadHeader(thread: x, staff: staff),
              const SizedBox(height: AppSpace.sm),
              if (hasOlder && onOlder != null)
                Align(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                    onPressed: loadingOlder ? null : onOlder,
                    icon: loadingOlder ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_less_rounded),
                    label: Text(t('رسائل أقدم', 'Older messages')),
                  ),
                ),
              for (final m in messages) AdvMessageBubble(message: m, onOpenAttachment: onOpenAttachment),
              for (final q in waiting) AdvMessageBubble(message: AdvMessage(id: 0, mine: true, body: q.draft.body, attachments: q.draft.attachments), pending: true),
              for (final q in refused)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpace.xs),
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.05), borderRadius: AppRadius.chipAll, border: Border.all(color: c.danger.withValues(alpha: 0.25))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(t('لم تُرسل رسالة كُتبت دون اتصال', 'A message written offline was not sent'), style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    if ((q.message ?? '').isNotEmpty) Text(q.message!, style: AppType.meta(context)),
                    const SizedBox(height: AppSpace.xxs),
                    AdvTypedText(q.draft.body, maxLines: 3),
                    Wrap(spacing: AppSpace.xxs, children: [
                      if (onReopenQueued != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                          onPressed: () => onReopenQueued!(q),
                          icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
                          label: Text(t('تعديل وإعادة الإرسال', 'Edit and send again')),
                        ),
                      if (onDiscardQueued != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), foregroundColor: appInk(context, c.danger)),
                          onPressed: () => onDiscardQueued!(q),
                          icon: const Icon(Icons.delete_outline_rounded, size: AppIconSize.sm),
                          label: Text(t('حذف', 'Discard')),
                        ),
                    ]),
                  ]),
                ),
            ]),
          ),
        ),
      ),
      Material(
        color: c.surface,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                  child: x.closed
                      ? LayoutBuilder(builder: (context, box) {
                          final line = Row(children: [
                            ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, color: c.textMedium, size: AppIconSize.md)),
                            const SizedBox(width: AppSpace.xs),
                            Expanded(child: Text(t('المحادثة مغلقة', 'This conversation is closed'), style: AppType.body(context))),
                          ]);
                          if (onReopen == null) return line;
                          final narrow = box.maxWidth < 440 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
                          final reopen = AppButton.secondary(label: t('إعادة فتحها', 'Reopen'), icon: Icons.lock_open_rounded, expand: narrow, onPressed: onReopen);
                          if (!narrow) return Row(children: [Expanded(child: line), const SizedBox(width: AppSpace.sm), reopen]);
                          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [line, const SizedBox(height: AppSpace.xs), reopen]);
                        })
                      : (composer ?? const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The thread page
// ═════════════════════════════════════════════════════════════════════════════

class AdvThreadPage extends StatelessWidget {
  const AdvThreadPage({super.key, required this.orgId, required this.threadId, this.student = false, this.subject});
  final int orgId, threadId;
  final bool student;
  final String? subject;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: subject ?? t('محادثة', 'Conversation'),
        subtitle: t('الإرشاد الأكاديمي', 'Academic advising'),
        maxWidth: 960,
        child: _AdvThreadBody(orgId: orgId, threadId: threadId, student: student),
      );
}

class _AdvThreadBody extends StatefulWidget {
  const _AdvThreadBody({required this.orgId, required this.threadId, required this.student});
  final int orgId, threadId;
  final bool student;

  @override
  State<_AdvThreadBody> createState() => _AdvThreadBodyState();
}

class _AdvThreadBodyState extends State<_AdvThreadBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId, student: widget.student);
  final _store = AdvMessageStore.instance;
  final _body = TextEditingController();
  final _scroll = ScrollController();
  OrgPageRefresh? _refresh;
  StreamSubscription<LiveEvent>? _live;
  AdvThread? _thread;
  final List<AdvMessage> _messages = [];
  String? _next;
  AdvLoad _load = AdvLoad.loading;
  String? _error, _composeError;
  List<AdvAttachment> _attachments = const [];
  List<AdvQueuedMessage> _queued = const [];
  bool _sending = false, _uploading = false, _loadingOlder = false, _draftSaved = false;
  bool _online = AppConnectivity.instance.isOnline;
  Timer? _saveTimer;

  int get _org => widget.orgId;
  int get _tid => widget.threadId;
  bool get _staff => !widget.student;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _live = LiveEvents.instance.listen({LiveEvents.connectivity}, (_) {
      if (!mounted) return;
      final online = AppConnectivity.instance.isOnline;
      setState(() => _online = online);
      if (online) _store.flush();
    });
    _store.changes.addListener(_readQueue);
    _body.addListener(_onTyped);
    _restoreDraft();
    _readQueue();
    _reload();
    _store.flush();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _live?.cancel();
    _store.changes.removeListener(_readQueue);
    _saveTimer?.cancel();
    final d = AdvMessageDraft(body: _body.text, attachments: _attachments);
    if (d.worthKeeping) _store.saveDraft(_org, _tid, d);
    _body.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.thread(_tid), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        final d = r.data as AdvThreadDetail;
        _thread = d.thread;
        _messages
          ..clear()
          ..addAll(d.messages);
        _next = d.next;
        _load = AdvLoad.ready;
      } else if (_thread == null) {
        _load = advFailLoad(r);
        _error = advCommErrorText(r.error!);
      }
    });
    if (r.ok && mounted) {
      OrgPageRefresh.reportUpdated(context);
      _settleQueued();
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _older() async {
    setState(() => _loadingOlder = true);
    final r = await orgCall(() => _api.thread(_tid, before: _next), quiet: true);
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (r.ok) {
        final d = r.data as AdvThreadDetail;
        _messages.insertAll(0, [for (final m in d.messages) if (!_messages.any((x) => x.id == m.id)) m]);
        _next = d.next;
      }
    });
    if (!r.ok) showAppNotice(advCommErrorText(r.error!), error: true);
  }

  /// A message written offline that is already in the thread leaves the queue.
  Future<void> _settleQueued() async {
    final posted = {for (final m in _messages) if (m.clientId != null) m.clientId!};
    for (final q in _queued) {
      if (posted.contains(q.clientId)) await _store.discard(q);
    }
  }

  Future<void> _readQueue() async {
    final q = await _store.queued(_org, _tid);
    if (!mounted) return;
    final before = _queued.where((x) => !x.failed).length;
    setState(() => _queued = q);
    if (q.where((x) => !x.failed).length < before) _reload();
  }

  Future<void> _restoreDraft() async {
    final d = await _store.draft(_org, _tid);
    if (!mounted || d == null || _body.text.isNotEmpty) return;
    setState(() {
      _attachments = d.attachments;
      _draftSaved = true;
    });
    _body.text = d.body;
  }

  void _onTyped() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final d = AdvMessageDraft(body: _body.text, attachments: _attachments);
    await _store.saveDraft(_org, _tid, d);
    if (mounted && _draftSaved != d.worthKeeping) setState(() => _draftSaved = d.worthKeeping);
  }

  Future<void> _send() async {
    final d = AdvMessageDraft(body: _body.text, attachments: _attachments);
    final why = d.error();
    if (why != null) {
      setState(() => _composeError = why);
      return;
    }
    setState(() {
      _sending = true;
      _composeError = null;
    });
    _saveTimer?.cancel();
    final r = await _store.send(_org, _tid, d, student: widget.student);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r.state == AdvSendState.failed) {
        _composeError = advCommErrorText(r.error!);
      } else {
        _attachments = const [];
        _draftSaved = false;
        if (r.message != null) _messages.add(r.message!);
      }
    });
    if (r.state == AdvSendState.failed) {
      if (r.error!.code == 'advising_thread_closed') _reload();
      return;
    }
    _body.clear();
    _saveTimer?.cancel();
    if (r.state == AdvSendState.sent) {
      showAppNotice(t('أُرسلت الرسالة', 'Message sent'));
      _reload();
    } else {
      showAppNotice(t('محفوظة على هذا الجهاز · تُرسل عند عودة الاتصال', 'Saved on this device · will send when online'));
      _readQueue();
      _toBottom();
    }
  }

  Future<void> _attach() async {
    setState(() => _uploading = true);
    final a = await advPickAttachment(_api);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (a != null) _attachments = [..._attachments, a];
    });
    if (a != null) _saveDraft();
  }

  Future<void> _template() async {
    final x = _thread;
    if (x == null) return;
    String? me;
    String? org;
    try {
      me = context.read<MyAuthProvider>().currentUser?.name;
    } catch (_) {}
    try {
      final s = context.read<OrgSession>();
      if (s.currentId == _org) org = orgNameOf(s.current);
    } catch (_) {}
    final now = DateTime.now().toUtc();
    final text = await pickAdvTemplateText(context, _api, kinds: const ['message', 'outreach', 'support_request'], values: {
      'student_name': x.studentName,
      'advisor_name': ?me,
      'date': AppTime.date(now),
      'time': AppTime.time(now),
      'org_name': ?org,
    });
    if (text == null || !mounted) return;
    if (_body.text.trim().isNotEmpty) {
      final yes = await appConfirm(context, message: t('استبدال ما كتبته بنص القالب؟', 'Replace what you wrote with the template text?'), confirmLabel: t('استبدال', 'Replace'));
      if (!yes || !mounted) return;
    }
    _body.text = text;
  }

  Future<void> _setStatus(String status) async {
    final closing = status == 'closed';
    final yes = await appConfirm(
      context,
      confirmLabel: closing ? t('إغلاق', 'Close') : t('إعادة فتح', 'Reopen'),
      message: closing
          ? t('إغلاق المحادثة؟ يمكن إعادة فتحها لاحقاً.', 'Close the conversation? It can be reopened later.')
          : t('إعادة فتح المحادثة لتكملة الحديث؟', 'Reopen the conversation to continue?'),
    );
    if (!yes || !mounted) return;
    final r = await orgCall(() => _api.setThreadStatus(_tid, status), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(advCommErrorText(r.error!), error: true);
      return;
    }
    setState(() => _thread = r.data as AdvThread);
    showAppNotice(closing ? t('أُغلقت المحادثة', 'Conversation closed') : t('أُعيد فتح المحادثة', 'Conversation reopened'));
  }

  Future<void> _escalate() async {
    final note = TextEditingController();
    var busy = false;
    String? error;
    final done = await showAppSheet<AdvThread>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> submit() async {
            set(() {
              busy = true;
              error = null;
            });
            final r = await orgCall(() => _api.escalate(_tid, note.text), quiet: true);
            if (!ctx.mounted) return;
            if (!r.ok) {
              set(() {
                busy = false;
                error = advCommErrorText(r.error!);
              });
              return;
            }
            Navigator.pop(ctx, r.data as AdvThread);
          }

          return AppSheetContent(
            title: t('تصعيد المحادثة', 'Escalate the conversation'),
            children: [
              Text(
                t('تُنشأ معاملة شكوى في إدارة الإرشاد الأكاديمي ويُبلَّغ مديروها. لا تُنقل الرسائل إليها — اكتب ما يلزم في الملاحظة.',
                    'A complaint work item is opened in the Academic Advising department and its directors are told. The messages are not copied into it — write what is needed in the note.'),
                style: AppType.body(context),
              ),
              const SizedBox(height: AppSpace.sm),
              AdvTypedField(controller: note, label: t('ملاحظة للمعاملة', 'Note for the work item'), minLines: 3, maxLines: 6, maxLength: 4000, enabled: !busy),
              if (error != null) ...[
                const SizedBox(height: AppSpace.sm),
                AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!),
              ],
              const SizedBox(height: AppSpace.md),
              AppButton.danger(label: t('تصعيد', 'Escalate'), icon: Icons.north_rounded, expand: true, busy: busy, onPressed: submit),
            ],
          );
        }));
    if (done == null || !mounted) return;
    setState(() => _thread = done);
    showAppNotice(t('صُعّدت المحادثة إلى المعاملة #${done.workItemId}', 'Escalated to work item #${done.workItemId}'));
  }

  Future<void> _reopenQueued(AdvQueuedMessage q) async {
    final d = await _store.reopen(q);
    if (!mounted) return;
    setState(() {
      _attachments = d.attachments;
      _draftSaved = true;
    });
    _body.text = d.body;
  }

  @override
  Widget build(BuildContext context) {
    final x = _thread;
    final menu = <OrgMenuItem>[
      if (x != null && !x.closed) OrgMenuItem(icon: Icons.lock_outline_rounded, label: t('إغلاق المحادثة', 'Close the conversation'), onTap: () => _setStatus('closed')),
      if (x != null && _staff && !x.escalated && !x.closed) OrgMenuItem(icon: Icons.north_rounded, label: t('تصعيد إلى معاملة', 'Escalate to a work item'), danger: true, onTap: _escalate),
    ];
    return OrgPageBody(
      more: menu,
      child: AdvThreadView(
        load: _load,
        thread: x,
        messages: _messages,
        queued: _queued,
        staff: _staff,
        hasOlder: _next != null,
        loadingOlder: _loadingOlder,
        errorText: _error,
        scroll: _scroll,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onOlder: _older,
        onOpenAttachment: (a) => advOpenAttachment(context, _api, a),
        onReopen: () => _setStatus('open'),
        onDiscardQueued: (q) => _store.discard(q),
        onReopenQueued: _reopenQueued,
        composer: AdvMessageComposer(
          body: _body,
          attachments: _attachments,
          offline: !_online,
          draftSaved: _draftSaved && _online,
          uploading: _uploading,
          busy: _sending,
          error: _composeError,
          onAttach: _attach,
          onRemoveAttachment: (a) {
            setState(() => _attachments = [for (final y in _attachments) if (y.id != a.id) y]);
            _saveDraft();
          },
          onTemplate: _staff ? _template : null,
          onSend: _sending ? null : _send,
        ),
      ),
    );
  }
}

/// The templates of [kinds] as a sheet; the chosen one comes back with its placeholders filled from [values].
Future<String?> pickAdvTemplateText(BuildContext context, AdvCommApi api, {required List<String> kinds, Map<String, String> values = const {}}) async {
  final r = await orgCall(() => api.templates(), quiet: true);
  if (!context.mounted) return null;
  if (!r.ok) {
    showAppNotice(advCommErrorText(r.error!), error: true);
    return null;
  }
  final list = [for (final x in r.data as List<AdvTemplate>) if (x.active && kinds.contains(x.kind)) x];
  if (list.isEmpty) {
    showAppNotice(t('لا قوالب رسائل بعد', 'No message templates yet'), error: true);
    return null;
  }
  return showAppSheet<String>(
    context,
    (ctx) => AppSheetContent(
      title: t('إدراج قالب', 'Insert a template'),
      children: [
        for (final x in list)
          AdvRowCard(
            leading: Icon(Icons.description_outlined, color: ctx.colors.primary),
            title: x.name,
            subtitle: [advTemplateKindLabel(x.kind), x.body.replaceAll('\n', ' ')].join(' · '),
            onTap: () => Navigator.pop(ctx, advFillTemplate(x.body, values)),
          ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  A new conversation
// ═════════════════════════════════════════════════════════════════════════════

class AdvNewThreadForm extends StatelessWidget {
  const AdvNewThreadForm({
    super.key,
    required this.draft,
    required this.subject,
    required this.body,
    this.student = true,
    this.advisors = const [],
    this.studentName,
    this.uploading = false,
    this.busy = false,
    this.error,
    this.onKind,
    this.onAbout,
    this.onAboutUser,
    this.onPriority,
    this.onAttach,
    this.onRemoveAttachment,
    this.onSubmit,
  });

  final AdvThreadDraft draft;
  final TextEditingController subject, body;
  final bool student;

  /// A student's advisors (user id, name): the complaint may name one.
  final List<(int, String)> advisors;
  final String? studentName;
  final bool uploading, busy;
  final String? error;
  final ValueChanged<String>? onKind, onAbout, onPriority;
  final ValueChanged<int>? onAboutUser;
  final VoidCallback? onAttach, onSubmit;
  final ValueChanged<AdvAttachment>? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final complaint = d.kind == 'complaint';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!student && studentName != null) AdvInfoLine(icon: Icons.person_outline_rounded, text: t('إلى $studentName', 'To $studentName')),
      if (student) ...[
        AdvFieldLabel(t('النوع', 'Kind')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(label: t('سؤال أو طلب', 'A question or request'), icon: Icons.forum_outlined, selected: !complaint, onTap: busy || onKind == null ? () {} : () => onKind!('message')),
          AppChoiceChip(label: t('شكوى', 'A complaint'), icon: Icons.report_outlined, selected: complaint, onTap: busy || onKind == null ? () {} : () => onKind!('complaint')),
        ]),
        if (complaint) ...[
          const SizedBox(height: AppSpace.sm),
          AdvFieldLabel(t('الشكوى عن', 'The complaint is about')),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(label: t('أمر آخر', 'Something else'), selected: d.about != 'advisor', onTap: busy || onAbout == null ? () {} : () => onAbout!('other')),
            AppChoiceChip(label: t('مرشدي', 'My advisor'), icon: Icons.lock_outline_rounded, selected: d.about == 'advisor', onTap: busy || onAbout == null ? () {} : () => onAbout!('advisor')),
          ]),
          const SizedBox(height: AppSpace.xs),
          AppBanner(
            icon: d.about == 'advisor' ? Icons.lock_outline_rounded : Icons.info_outline_rounded,
            color: d.about == 'advisor' ? c.warning : null,
            text: d.about == 'advisor'
                ? t('تصل الشكوى إلى مدير الإرشاد الأكاديمي فقط، ولا يراها المرشد الذي تشكو منه.', 'The complaint goes to the advising director only; the advisor it is about never sees it.')
                : t('تصل الشكوى إلى مرشدك ليتابعها معك، ويمكن تصعيدها إلى الإدارة.', 'The complaint goes to your advisor to follow up with you, and can be escalated.'),
          ),
          if (d.about == 'advisor' && advisors.length > 1) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final a in advisors)
                AppChoiceChip(label: a.$2, icon: Icons.person_outline_rounded, selected: (d.aboutUserId ?? advisors.first.$1) == a.$1, onTap: busy || onAboutUser == null ? () {} : () => onAboutUser!(a.$1)),
            ]),
          ],
        ],
        const SizedBox(height: AppSpace.md),
      ],
      AppField(controller: subject, label: t('العنوان', 'Subject')),
      const SizedBox(height: AppSpace.sm),
      AdvTypedField(controller: body, label: t('الرسالة', 'Message'), minLines: 4, maxLines: 10, maxLength: advMessageMax, enabled: !busy),
      if (student) ...[
        const SizedBox(height: AppSpace.sm),
        AdvFieldLabel(t('الأهمية', 'Priority'), hint: d.priority == 'urgent' ? t('يُبلَّغ المرشد ومدير الإرشاد فوراً', 'Your advisor and the advising director are told at once') : null),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final p in advThreadPriorities) AppChoiceChip(label: advPriorityLabel(p), selected: d.priority == p, onTap: busy || onPriority == null ? () {} : () => onPriority!(p)),
        ]),
      ],
      const SizedBox(height: AppSpace.sm),
      if (d.attachments.isNotEmpty) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in d.attachments) AdvAttachmentChip(attachment: a, onRemove: busy || onRemoveAttachment == null ? null : () => onRemoveAttachment!(a)),
        ]),
        const SizedBox(height: AppSpace.xs),
      ],
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: busy || uploading || onAttach == null || d.attachments.length >= advMaxAttachments ? null : onAttach,
          icon: uploading ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.attach_file_rounded),
          label: Text(t('إرفاق ملف (حتى 5)', 'Attach a file (up to 5)')),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.send_rounded, label: complaint ? t('إرسال الشكوى', 'Send the complaint') : t('إرسال', 'Send'), busy: busy, onPressed: uploading ? null : onSubmit),
    ]);
  }
}

/// Starts a conversation: a student with their advisors ([advisors] for a complaint about one), staff with the
/// student [memberId]. Returns the thread.
Future<AdvThread?> showAdvNewThreadSheet(BuildContext context, AdvCommApi api, {int? memberId, String? studentName, List<(int, String)> advisors = const [], String kind = 'message'}) {
  final subject = TextEditingController();
  final body = TextEditingController();
  var draft = AdvThreadDraft(memberId: api.student ? null : memberId, kind: kind, clientId: 't${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}');
  var busy = false, uploading = false;
  String? error;
  return showAppSheet<AdvThread>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final d = draft.copyWith(subject: subject.text, body: body.text);
          final why = d.error();
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.startThread(d), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          final (thread, _) = r.data as (AdvThread, List<AdvMessage>);
          showAppNotice(d.kind == 'complaint'
              ? (d.about == 'advisor' ? t('أُرسلت الشكوى إلى مدير الإرشاد', 'Complaint sent to the advising director') : t('أُرسلت الشكوى', 'Complaint sent'))
              : t('أُرسلت الرسالة', 'Message sent'));
          Navigator.pop(ctx, thread);
        }

        Future<void> attach() async {
          set(() => uploading = true);
          final a = await advPickAttachment(api);
          if (!ctx.mounted) return;
          set(() {
            uploading = false;
            if (a != null) draft = draft.copyWith(attachments: [...draft.attachments, a]);
          });
        }

        return AppSheetContent(
          title: kind == 'complaint' ? t('شكوى جديدة', 'New complaint') : t('رسالة جديدة', 'New message'),
          children: [
            AdvNewThreadForm(
              draft: draft,
              subject: subject,
              body: body,
              student: api.student,
              advisors: advisors,
              studentName: studentName,
              uploading: uploading,
              busy: busy,
              error: error,
              onKind: (k) => set(() => draft = draft.copyWith(kind: k)),
              onAbout: (a) => set(() => draft = draft.copyWith(about: a)),
              onAboutUser: (u) => set(() => draft = draft.copyWith(aboutUserId: () => u)),
              onPriority: (p) => set(() => draft = draft.copyWith(priority: p)),
              onAttach: attach,
              onRemoveAttachment: (a) => set(() => draft = draft.copyWith(attachments: [for (final x in draft.attachments) if (x.id != a.id) x])),
              onSubmit: submit,
            ),
          ],
        );
      }));
}
