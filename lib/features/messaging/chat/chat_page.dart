// lib/features/messaging/chat/chat_page.dart — Alfaheem Messages (D-330, D-375): the one chat design for every role.
//
//   ChatHomePage(initialConversationId:, startPeerId:…)  the list; from 760 px of pane the list and the open chat side by
//                                                        side, below that a chat opens as a full-screen ChatThreadPage
//   ChatThreadView / ChatThreadPage                      one chat: header, messages, composer
//
// Kill switch `chat`. Reached through ChatEntryIcon in every role's shell and home header (route '/chat').
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import 'package:flutter_education_app/features/messaging/chat/chat_api.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_sheets.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_widgets.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_education_app/features/profile/teacher/t2b_parts.dart';
import 'package:provider/provider.dart';

const kChatFeatureKey = 'chat';
const double kChatSplitFrom = 760;

String chatErrorText(Object e) {
  final x = ApiException.from(e);
  final d = apiErrorDetail(x);
  if (AppConfig.lang != 'ar' && d['message_en'] is String) return d['message_en'] as String;
  return x.message;
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key, this.initialConversationId, this.startPeerId, this.startCourseId, this.startOrgId});
  final int? initialConversationId;
  final int? startPeerId, startCourseId, startOrgId;

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> with WidgetsBindingObserver {
  final ChatHub _hub = ChatHub.instance;
  late final EventOrPoll _presence = EventOrPoll(
    poll: () async {
      await _hub.api.presence(true).catchError((_) {});
    },
    every: const Duration(seconds: 45),
    fallbackEvery: const Duration(seconds: 45),
    names: const {},
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hub.start();
    _hub.load();
    _presence.start(pollNow: true);
    final peer = widget.startPeerId;
    if (peer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startWith(peer, widget.startCourseId, widget.startOrgId));
    } else if (widget.initialConversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.initialConversationId!));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presence.start(pollNow: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _presence.stop();
      _hub.api.presence(false).catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presence.stop();
    _hub.api.presence(false).catchError((_) {});
    _hub.selectedId = null;
    super.dispose();
  }

  Future<void> _startWith(int peer, int? course, int? org) async {
    try {
      final conv = await _hub.api.start(peerId: peer, courseId: course, orgId: org);
      _open(conv.id);
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
    }
  }

  bool _split = false;

  void _open(int id) {
    if (_split) {
      setState(() => _hub.selectedId = id);
      return;
    }
    // over the role's tabs: a conversation is a full-screen place on a phone
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ChatThreadPage(conversationId: id)));
  }

  Future<void> _newChat() async {
    final ct = await showChatContactPicker(context);
    if (ct == null || !mounted) return;
    if (ct.conversationId != null) {
      _open(ct.conversationId!);
    } else {
      _startWith(ct.user.id, ct.course?.id, ct.orgId);
    }
  }

  void _openRequests() {
    _hub.loadRequests();
    showAppSheet<void>(context, (sheet) => ChatRequestsSheet(hub: _hub, onOpen: (id) {
      Navigator.of(sheet).pop();
      _open(id);
    }));
  }

  @override
  Widget build(BuildContext context) {
    // a teacher's messages wear the teacher hero (redesign T2b, Tea2Chat): what is waiting, New message, and the
    // list's filters as its pills; the list's own chips step aside
    final teacher = _isTeacher(context);
    final page = BasePage(
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final split = box.maxWidth >= kChatSplitFrom;
          _split = split;
          return ListenableBuilder(
            listenable: _hub,
            builder: (context, _) {
              final selected = _hub.selectedId;
              final list = ChatListView(
                hub: _hub,
                onOpen: _open,
                onNewChat: _newChat,
                onRequests: _openRequests,
                onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
                heroFilters: teacher,
              );
              Widget withHero(Widget body) => !teacher
                  ? body
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      T2bChatHero(hub: _hub, onNewChat: _newChat),
                      Expanded(child: body),
                    ]);
              if (!split) {
                // the window was narrowed with a chat open: it stays open, full-screen
                if (selected == null) return withHero(list);
                return ChatThreadView(key: ValueKey(selected), conversationId: selected, onBack: () => setState(() => _hub.selectedId = null), onLeave: () => setState(() => _hub.selectedId = null));
              }
              return withHero(Row(children: [
                SizedBox(width: (box.maxWidth * 0.3).clamp(340.0, 420.0), child: list),
                VerticalDivider(width: 1, color: context.colors.divider.withValues(alpha: 0.6)),
                Expanded(
                  child: selected == null
                      ? _NoChatSelected(onNewChat: _newChat)
                      : ChatThreadView(
                          key: ValueKey(selected),
                          conversationId: selected,
                          showBack: false,
                          onLeave: () => setState(() => _hub.selectedId = null),
                        ),
                ),
              ]));
            },
          );
        }),
      ),
    );
    return teacher ? T2Scope(child: page) : page;
  }

  bool _isTeacher(BuildContext context) {
    try {
      return context.read<MyAuthProvider>().currentUser?.role == 'teacher';
    } on ProviderNotFoundException {
      return false;
    }
  }
}

/// The teacher's messages hero (Tea2Chat): how many chats wait (unread and requests), one line, New message, and the
/// list's filters as glass pills (All, Unread, then the roles the server offers, Groups, Pinned).
class T2bChatHero extends StatelessWidget {
  const T2bChatHero({super.key, required this.hub, required this.onNewChat});

  final ChatHub hub;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final unread = hub.conversations.where((c) => c.unread > 0).length;
    final requests = hub.requestCount;
    final title = unread == 0 && requests == 0
        ? 't2_chat_calm'.tr
        : [
            if (unread > 0) countText(unread, ar1: 'رسالة جديدة', ar2: 'رسالتين جديدة', arFew: '{n} رسائل جديدة', arMany: '{n} رسالة جديدة', en1: '1 new message', en: '{n} new messages'),
            if (requests > 0) countText(requests, ar1: 'طلب', ar2: 'طلبين', arFew: '{n} طلبات', arMany: '{n} طلبًا', en1: '1 request', en: '{n} requests'),
          ].join(AppConfig.lang == 'ar' ? ' و' : ' and ');
    final pills = <(String, String?, int?, VoidCallback)>[
      ('chat_filter_all'.tr, 'all', null, () => hub.applyFilters(filter: 'all', clearCourse: true, clearRole: true)),
      ('chat_filter_unread'.tr, 'unread', unread, () => hub.applyFilters(filter: 'unread', clearRole: true)),
      for (final r in hub.filterRoles) ('chat_role_$r'.tr, 'role:$r', null, () => hub.applyFilters(filter: 'all', role: r)),
      ('chat_filter_groups'.tr, 'groups', null, () => hub.applyFilters(filter: 'groups', clearRole: true)),
      ('chat_filter_pinned'.tr, 'pinned', null, () => hub.applyFilters(filter: 'pinned', clearRole: true)),
    ];
    final current = hub.role != null ? 'role:${hub.role}' : hub.filter;
    final index = pills.indexWhere((p) => p.$2 == current);
    final wide = MediaQuery.sizeOf(context).width >= kChatSplitFrom;
    final newButton = AppButton.primary(
        key: const ValueKey('chat.hero.new'), label: 'chat_new_chat'.tr, icon: Icons.edit_outlined, onPressed: onNewChat);
    return AppHero(
      overlap: false,
      wipe: false,
      title: unread == 0 && requests == 0 ? title : 't2_chat_waiting'.tr.replaceAll('{what}', title),
      subtitle: 't2_chat_sub'.tr,
      trailing: wide ? Align(alignment: AlignmentDirectional.topEnd, child: newButton) : null,
      actions: [if (!wide) Align(alignment: AlignmentDirectional.centerStart, child: newButton)],
      bottom: T2bHeroPills(
        index: index < 0 ? 0 : index,
        onChanged: (i) => pills[i].$4(),
        items: [for (final p in pills) T2bPill(p.$1, count: p.$3, key: 'chat.pill.${p.$2}')],
      ),
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: chatThreadBg(c),
      child: CustomPaint(
        painter: _DotWallpaper(c.textMedium.withValues(alpha: c.isDark ? 0.07 : 0.06)),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                child: Icon(Icons.forum_rounded, size: AppIconSize.hero + 8, color: chatInk(c)),
              ),
              const SizedBox(height: AppSpace.md),
              Text('chat_empty_detail_title'.tr, style: AppType.headline(context), textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text('chat_empty_detail_body'.tr, style: appText(13.5, c: c.textMedium, h: 1.45), textAlign: TextAlign.center),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(label: 'chat_new_chat'.tr, icon: Icons.edit_outlined, onPressed: onNewChat),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The inbox: message requests on top, then the chats by their last message, pinned first (D-542).
class ChatListView extends StatelessWidget {
  const ChatListView(
      {super.key, required this.hub, required this.onOpen, required this.onNewChat, this.onRequests, this.onBack, this.heroFilters = false});

  /// The filters sit on a hero above the list (a teacher's page, T2b): no chips row of its own.
  final bool heroFilters;
  final ChatHub hub;
  final void Function(int id) onOpen;
  final VoidCallback onNewChat;
  final VoidCallback? onRequests;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // four chips everyone understands; the rest (a role, a course) waits behind "More"
    final moreOn = hub.role != null || hub.courseId != null;
    final hasMore = hub.filterRoles.isNotEmpty || hub.filterCourses.isNotEmpty;
    final filterChips = <Widget>[
      ChatFilterChip(label: 'chat_filter_all'.tr, selected: hub.filter == 'all' && !moreOn, onTap: () => hub.applyFilters(filter: 'all', clearCourse: true, clearRole: true)),
      ChatFilterChip(label: 'chat_filter_unread'.tr, selected: hub.filter == 'unread', onTap: () => hub.applyFilters(filter: hub.filter == 'unread' ? 'all' : 'unread')),
      ChatFilterChip(label: 'chat_filter_groups'.tr, selected: hub.filter == 'groups', onTap: () => hub.applyFilters(filter: hub.filter == 'groups' ? 'all' : 'groups')),
      ChatFilterChip(label: 'chat_filter_pinned'.tr, selected: hub.filter == 'pinned', onTap: () => hub.applyFilters(filter: hub.filter == 'pinned' ? 'all' : 'pinned')),
      if (hasMore) Builder(builder: (context) => ChatFilterChip(label: 'chat_filter_more'.tr, icon: Icons.tune_rounded, selected: moreOn, onTap: () => _moreFilters(context))),
    ];
    final showBlocked = !AppConfig.disableList.contains('chat.blocking');
    return Material(
      color: c.cardBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: kChatBarHeight,
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, 0),
          child: Row(children: [
            if (onBack != null) ...[
              AppBackButton(onPressed: onBack),
              const SizedBox(width: AppSpace.xxs),
            ],
            Expanded(child: Text('chat_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context))),
            if (showBlocked)
              IconButton(
                tooltip: 'chat_blocked_people'.tr,
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                icon: Icon(Icons.shield_outlined, size: AppIconSize.lg - 2, color: c.textMedium),
                onPressed: () => AppShellNav.navigatorFor(context).pushNamed('/chat/blocks'),
              ),
            IconButton(
              tooltip: 'chat_new_chat'.tr,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.edit_square, size: AppIconSize.lg - 2, color: chatInk(c)),
              onPressed: onNewChat,
            ),
          ]),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: AppConnectivity.instance.online,
          builder: (_, online, _) => online ? const SizedBox.shrink() : const ChatOfflineStrip(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.xs),
          child: AppSearchField(hint: 'chat_search_hint'.tr, dense: true, onChanged: (q) => hub.applyFilters(search: q)),
        ),
        if (!heroFilters)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppHScroll(
            thumbVisibility: false,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Row(children: [
              for (var i = 0; i < filterChips.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xs),
                filterChips[i],
              ],
            ]),
          ),
        ),
        Divider(height: 1, thickness: 1, color: c.divider.withValues(alpha: 0.5)),
        Expanded(child: _rows(context)),
      ]),
    );
  }

  void _moreFilters(BuildContext context) {
    showAppSheet<void>(
      context,
      (sheet) => ListenableBuilder(
        listenable: hub,
        builder: (sheet, _) => AppSheetContent(title: 'chat_filter_more'.tr, children: [
          if (hub.filterRoles.isNotEmpty) ...[
            Text('chat_filter_person'.tr, style: appText(13, w: FontWeight.w600, c: context.colors.textDark)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final r in const ['teacher', 'parent', 'student'])
                if (hub.filterRoles.contains(r))
                  AppChoiceChip(label: 'chat_role_$r'.tr, selected: hub.role == r, onTap: () => hub.applyFilters(role: hub.role == r ? null : r, clearRole: hub.role == r)),
            ]),
            const SizedBox(height: AppSpace.md),
          ],
          if (hub.filterCourses.isNotEmpty) ...[
            Text('chat_filter_course'.tr, style: appText(13, w: FontWeight.w600, c: context.colors.textDark)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final course in hub.filterCourses)
                AppChoiceChip(label: course.label, selected: hub.courseId == course.id, onTap: () => hub.applyFilters(courseId: hub.courseId == course.id ? null : course.id, clearCourse: hub.courseId == course.id)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _rows(BuildContext context) {
    if (hub.loading && hub.conversations.isEmpty && hub.requestCount == 0) return const AppListSkeleton(items: 8);
    if (hub.error != null && hub.conversations.isEmpty) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: hub.error!, actionLabel: 'chat_retry'.tr, onAction: () => hub.load());
    }
    final filtered = !hub.plainList;
    if (hub.conversations.isEmpty && (filtered || hub.requestCount == 0)) {
      return AppEmpty(
        icon: filtered ? Icons.filter_alt_off_rounded : Icons.forum_outlined,
        title: filtered ? 'chat_none_filtered'.tr : 'chat_none_title'.tr,
        message: filtered ? null : 'chat_none_body'.tr,
        actionLabel: filtered ? null : 'chat_new_chat'.tr,
        onAction: filtered ? null : onNewChat,
      );
    }
    final entries = <Object>[
      if (hub.requestCount > 0 && !filtered) 'requests',
      ...hub.conversations,
    ];
    return AppRefresh(
      onRefresh: () => hub.load(silent: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 300) hub.loadMore();
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs - 2, AppSpace.xxs, AppSpace.xs - 2, AppSpace.lg),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            if (e == 'requests') return ChatRequestsRow(count: hub.requestCount, onTap: () => onRequests?.call());
            final conv = e as ChatConversation;
            return ChatConversationTile(
              key: ValueKey('chat-row-${conv.id}'),
              conversation: conv,
              myId: hub.myId,
              selected: hub.selectedId == conv.id,
              typingName: hub.typing[conv.id],
              draft: hub.drafts[conv.id],
              pointerFirst: chatEnterSends,
              onTap: () => onOpen(conv.id),
              onMenu: (anchor) => showChatRowActions(context, conv, anchor: anchor),
            );
          },
        ),
      ),
    );
  }
}

/// The requests waiting on me: one card each, Accept · Decline · Block.
class ChatRequestsSheet extends StatefulWidget {
  const ChatRequestsSheet({super.key, required this.hub, required this.onOpen});
  final ChatHub hub;
  final void Function(int id) onOpen;

  @override
  State<ChatRequestsSheet> createState() => _ChatRequestsSheetState();
}

class _ChatRequestsSheetState extends State<ChatRequestsSheet> {
  final Set<int> _busy = {};

  Future<void> _act(int id, Future<void> Function() action) async {
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _block(ChatConversation conv) async {
    final ok = await appConfirm(context, message: '${'chat_request_block_confirm'.tr} ${conv.title}?', danger: true, confirmLabel: 'chat_block'.tr);
    if (ok) _act(conv.id, () => widget.hub.blockRequest(conv.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.hub,
      builder: (context, _) {
        final items = widget.hub.requests;
        return AppSheetContent(title: 'chat_requests'.tr, children: [
          Text('chat_requests_note'.tr, style: appText(12.5, w: FontWeight.w400, c: context.colors.textMedium, h: 1.4)),
          const SizedBox(height: AppSpace.sm),
          if (widget.hub.requestsLoading && items.isEmpty) const AppListSkeleton(items: 3),
          if (!widget.hub.requestsLoading && items.isEmpty) AppEmpty(icon: Icons.mark_email_read_outlined, title: 'chat_requests_none'.tr),
          for (final r in items) ...[
            ChatRequestCard(
              conversation: r,
              busy: _busy.contains(r.id),
              onOpen: () => widget.onOpen(r.id),
              onAccept: () => _act(r.id, () async {
                final conv = await widget.hub.acceptRequest(r.id);
                widget.onOpen(conv.id);
              }),
              onDecline: () => _act(r.id, () => widget.hub.declineRequest(r.id)),
              onBlock: () => _block(r),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ]);
      },
    );
  }
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({super.key, required this.conversationId});
  final int conversationId;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // the bubble must not sit on the composer
  }

  @override
  void dispose() {
    AppAssistant.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BasePage(child: SafeArea(child: ChatThreadView(conversationId: widget.conversationId)));
}

/// One open chat: the header, the messages and the composer. A subtle dot wallpaper sits behind the messages.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({super.key, required this.conversationId, this.showBack = true, this.controller, this.onLeave, this.onBack});
  final int conversationId;
  final bool showBack;

  /// What the back arrow does; default: the page pops.
  final VoidCallback? onBack;
  final ChatThreadController? controller;

  /// The chat is gone from here (a request declined): close it. Default: the page pops.
  final VoidCallback? onLeave;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> with WidgetsBindingObserver {
  late final ChatThreadController _t = widget.controller ?? ChatHub.instance.acquire(widget.conversationId);
  late final bool _ownsController = widget.controller == null;
  final _scroll = ScrollController();
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<ChatLocalFile> _files = [];
  final _centerKey = GlobalKey();
  Timer? _saveDraft;
  bool _draftTouched = false;
  bool _deciding = false;

  /// The list is at the newest message. Scrolled up, new messages must not move what is being read.
  bool _atLatest = true;
  String? _newestKey;

  /// While set, this message stays the scroll list's fixed point: newer ones grow below it without moving anything.
  String? _anchorKey;

  /// Where the fixed point sits, 0 = the bottom. A chat opened on many unread messages holds its first one near the top.
  double _anchorAt = 0;

  /// Opened at the first unread message once (the first page has arrived).
  bool _placed = false;

  /// The message the composer answers (D-540).
  ChatReplyRef? _replyTo;

  /// The message a quote just jumped to, tinted for a moment.
  String? _flashKey;
  Timer? _flashTimer;

  /// What is built right now, by message: a jump to a quoted message scrolls until it is here.
  final Map<String, BuildContext> _built = {};

  ChatHub get _hub => _t.hub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.text = _hub.drafts[widget.conversationId] ?? '';
    _newestKey = _t.messages.firstOrNull?.clientId;
    _t.addListener(_onUpdate);
    if (_ownsController) {
      _t.open().then((_) {
        _applyDraft();
        _placeAtUnread();
      });
    }
    _scroll.addListener(_onScroll);
  }

  /// Many unread messages: the chat opens on the first of them, under its line, instead of at the very end. Reaching the
  /// end marks them read (a chat left halfway keeps its place and its count).
  void _placeAtUnread() {
    if (_placed || !mounted) return;
    _placed = true;
    if (!_t.startsAtUnread) return;
    setState(() {
      _anchorKey = _t.firstUnreadKey;
      _anchorAt = 0.74;
      _atLatest = false;
    });
  }

  /// On a cold start the drafts were not read yet when the screen was built.
  void _applyDraft() {
    if (!mounted || _draftTouched || _text.text.isNotEmpty) return;
    final d = _hub.drafts[widget.conversationId];
    if (d == null || d.isEmpty) return;
    setState(() => _text.text = d);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _t.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDraft?.cancel();
    _flashTimer?.cancel();
    if (_draftTouched) _hub.setDraft(widget.conversationId, _text.text);
    _t.removeListener(_onUpdate);
    if (_ownsController) _hub.release(_t);
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  int? _privateShown;

  void _onUpdate() {
    final to = _t.privateChatId;
    if (to != null && to != _privateShown) {
      _privateShown = to;
      showAppNotice('sc_chat_reply_private'.tr, actionLabel: 'sc_chat_open_private'.tr, onAction: () {
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ChatThreadPage(conversationId: to)));
      });
    }
    final newest = _t.messages.firstOrNull?.clientId;
    if (newest != _newestKey) {
      // scrolled up and something new arrived at the bottom: what was the bottom stays where it is
      if (!_atLatest && _anchorKey == null && _newestKey != null) _anchorKey = _newestKey;
      _newestKey = newest;
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.extentAfter < 400) _t.loadOlder();
    if (_anchorKey != null && pos.pixels <= pos.minScrollExtent + 2) _collapseAnchor();
    final atLatest = pos.pixels <= pos.minScrollExtent + 120;
    if (atLatest != _atLatest) {
      _atLatest = atLatest;
      _t.setAtLatest(atLatest);
    }
  }

  void _collapseAnchor() {
    setState(() {
      _anchorKey = null;
      _anchorAt = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Older than what is loaded: pages come in first. Then forward until it is built, and it flashes.
  Future<void> _jumpTo(int id) async {
    for (var i = 0; i < 12 && !_t.messages.any((m) => m.id == id) && _t.hasMore; i++) {
      await _t.loadOlder();
      if (!mounted) return;
    }
    final target = _t.messages.where((m) => m.id == id).firstOrNull;
    if (target == null) {
      showAppNotice('chat_quote_gone'.tr);
      return;
    }
    for (var i = 0; i < 80 && !_built.containsKey(target.clientId) && _scroll.hasClients; i++) {
      final pos = _scroll.position;
      final next = (pos.pixels + pos.viewportDimension * 0.8).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (next == pos.pixels) break;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final at = _built[target.clientId];
    if (at == null || !at.mounted) return;
    await Scrollable.ensureVisible(at, duration: AppMotion.of(context).slow, curve: AppMotion.curve, alignment: 0.45);
    if (!mounted) return;
    setState(() => _flashKey = target.clientId);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashKey = null);
    });
  }

  /// Back to the newest message: a jump after sending, a glide from the button.
  void _toLatest({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final duration = animate ? AppMotion.of(context).slow : Duration.zero;
    if (_anchorKey != null && duration == Duration.zero) {
      _collapseAnchor();
    } else if (duration == Duration.zero) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(_scroll.position.minScrollExtent, duration: duration, curve: AppMotion.curve);
    }
    if (duration == Duration.zero && !_atLatest) {
      _atLatest = true;
      _t.setAtLatest(true);
    }
  }

  void _onChanged(String v) {
    _draftTouched = true;
    setState(() {});
    _saveDraft?.cancel();
    _saveDraft = Timer(const Duration(milliseconds: 450), () => _hub.setDraft(widget.conversationId, _text.text));
    _t.typingChanged(v.trim().isNotEmpty);
  }

  void _startReply(ChatMessage m) {
    final ref = ChatReplyRef.of(m);
    if (ref == null) return;
    setState(() => _replyTo = ref);
    _focus.requestFocus();
  }

  void _copy(ChatMessage m) {
    final body = (m.body ?? '').trim();
    if (body.isEmpty) return;
    Clipboard.setData(ClipboardData(text: body));
    showAppNotice('chat_copied'.tr);
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty && _files.isEmpty) return;
    final files = List<ChatLocalFile>.from(_files);
    final reply = _replyTo;
    _saveDraft?.cancel();
    _text.clear();
    _draftTouched = false;
    setState(() {
      _files.clear();
      _replyTo = null;
    });
    _hub.setDraft(widget.conversationId, '');
    _t.send(text, files: files, replyTo: reply);
    _toLatest();
    _focus.requestFocus();
  }

  Future<void> _attach() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return;
    final add = <ChatLocalFile>[];
    for (final f in picked.take(10 - _files.length)) {
      final size = (await f.length()) ?? 0;
      final image = ChatLocalFile(name: f.name).isImage;
      // bytes: always on the web; for a picture elsewhere too, so the composer and the bubble can show it (web-safe, no File)
      final bytes = kIsWeb || (image && size < 8 * 1024 * 1024) ? await f.readAsBytes() : null;
      add.add(ChatLocalFile(name: f.name, bytes: bytes, path: kIsWeb ? null : f.path, size: size));
    }
    if (mounted) setState(() => _files.addAll(add));
    _focus.requestFocus();
  }

  final Map<int, Future<String>> _urls = {};
  Future<String> _imageUrl(ChatAttachment a) => _urls[a.id] ??= _hub.api.attachmentLink(a.id);

  Future<void> _openLink(String url) async {
    await openExternalLink(url);
  }

  Future<void> _openAttachment(ChatAttachment a) async {
    try {
      final url = await _hub.api.attachmentLink(a.id, inline: a.image);
      if (a.image && mounted) {
        showChatImage(context, url, a.name);
      } else {
        await openExternalLink(url);
      }
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
    }
  }

  void _showInfo() {
    final conv = _t.conversation;
    if (conv != null) showChatInfoSheet(context, conv, onChanged: _t.reloadHeader);
  }

  void _leave() {
    final leave = widget.onLeave;
    if (leave != null) {
      leave();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _decide(Future<void> Function() action, {bool leave = false}) async {
    setState(() => _deciding = true);
    try {
      await action();
      if (leave && mounted) _leave();
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
    }
    if (mounted) setState(() => _deciding = false);
  }

  Future<void> _blockRequest(ChatConversation conv) async {
    final ok = await appConfirm(context, message: '${'chat_request_block_confirm'.tr} ${conv.title}?', danger: true, confirmLabel: 'chat_block'.tr);
    if (ok) _decide(() => _hub.blockRequest(conv.id), leave: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = _t.conversation;
    return ColoredBox(
      color: chatThreadBg(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ChatHeader(conversation: conv, typingName: _t.typingName, showBack: widget.showBack, onBack: widget.onBack, onInfo: _showInfo),
        ValueListenableBuilder<bool>(
          valueListenable: AppConnectivity.instance.online,
          builder: (_, online, _) => online ? const SizedBox.shrink() : const ChatOfflineStrip(),
        ),
        if (conv?.announceOnly == true) const ScAnnouncementsBanner(),
        Expanded(child: _body(c)),
        _composer(conv),
      ]),
    );
  }

  Widget _body(ThemeConfigProvider c) {
    if (_t.loading && _t.messages.isEmpty) return const ChatThreadSkeleton();
    if (_t.error != null && _t.messages.isEmpty && _t.conversation == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: _t.error!, actionLabel: 'chat_retry'.tr, onAction: () => _t.open());
    }
    if (_t.messages.isEmpty) return _EmptyThread(conversation: _t.conversation);
    final msgs = _t.messages;
    final conv = _t.conversation;
    final group = conv?.isGroup ?? false;
    final myId = _hub.myId;
    final canReply = conv?.composer == ChatComposerState.open;
    final pointerFirst = chatEnterSends;
    final showTyping = _t.typingName != null && _atLatest;
    // what the list draws, bottom to top: the typing slot, the messages, "loading older"
    final items = <int>[if (showTyping) -1, for (var i = 0; i < msgs.length; i++) i, if (_t.loadingOlder) -2];
    final anchorIdx = _anchorKey == null ? -1 : items.indexWhere((x) => x >= 0 && msgs[x].clientId == _anchorKey);
    final below = anchorIdx > 0 ? items.sublist(0, anchorIdx) : const <int>[];
    final above = anchorIdx > 0 ? items.sublist(anchorIdx) : items;

    String keyOf(int code) => code < 0 ? 'x$code' : 'm${msgs[code].clientId}';

    return LayoutBuilder(builder: (context, box) {
      final column = box.maxWidth > kChatColumnMaxWidth ? kChatColumnMaxWidth : box.maxWidth;
      final inner = column - 2 * AppSpace.md;
      final bubbleWidth = chatBubbleWidth(inner);
      Widget item(int code) {
        if (code == -1) {
          // the dots open upwards, so the message above slides out of their way instead of jumping
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.of(context).fast,
            curve: AppMotion.curve,
            builder: (_, v, child) => ClipRect(child: Align(alignment: Alignment.bottomCenter, heightFactor: v, child: child)),
            child: ChatTypingBubble(name: group ? _t.typingName : null),
          );
        }
        if (code == -2) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        final m = msgs[code];
        final older = code + 1 < msgs.length ? msgs[code + 1] : null;
        final newer = code > 0 ? msgs[code - 1] : null;
        bool together(ChatMessage a, ChatMessage b) => a.senderId == b.senderId && b.createdAt.difference(a.createdAt) <= const Duration(minutes: 5) && chatSameDay(a.createdAt, b.createdAt);
        final runStart = older == null || !together(older, m) || _t.firstUnreadKey == m.clientId;
        final runEnd = newer == null || !together(m, newer) || _t.firstUnreadKey == newer.clientId;
        final mine = m.senderId == myId;
        final showDate = older == null || !chatSameDay(older.createdAt, m.createdAt);
        final failed = m.sendState == ChatSendState.failed;
        final sent = m.id != null;
        final bubble = ChatBubble(
          message: m,
          mine: mine,
          tick: chatTickFor(m, peerReadId: group ? null : conv?.peerReadId, peerDeliveredId: group ? null : conv?.peerDeliveredId),
          showSender: group && runStart,
          runStart: runStart,
          runEnd: runEnd,
          maxWidth: bubbleWidth,
          myId: myId,
          pointerFirst: pointerFirst,
          highlight: _flashKey == m.clientId,
          imageOf: _imageUrl,
          onOpenAttachment: _openAttachment,
          onLink: _openLink,
          onReply: sent && canReply && !m.deleted ? () => _startReply(m) : null,
          onActions: conv == null || !sent ? null : (anchor) => showChatMessageActions(context, conv, m, mine: mine, anchor: anchor, onReply: canReply && !m.deleted ? () => _startReply(m) : null, onCopy: () => _copy(m)),
          onQuoteTap: m.replyTo == null ? null : () => _jumpTo(m.replyTo!.id),
          onRetry: failed ? () => _t.retry(m) : null,
          onDiscard: failed ? () => _t.discard(m) : null,
        );
        final row = group && !mine
            ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 34,
                  child: runEnd ? Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: AppAvatar(name: m.senderName ?? '', url: m.senderImage, size: 28)) : null,
                ),
                Expanded(child: bubble),
              ])
            : bubble;
        return _Tracked(
          id: m.clientId,
          built: _built,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showDate) ChatDateChip(label: chatDayLabel(m.createdAt)),
            if (_t.firstUnreadKey == m.clientId) const ChatUnreadDivider(),
            row,
            if (mine && runEnd && (m.privateReply || conv?.announceOnly == true)) const ScPrivateReplyNote(),
          ]),
        );
      }

      Widget sliver(List<int> rows, {bool closestFirst = false}) {
        final at = <String, int>{for (var i = 0; i < rows.length; i++) keyOf(rows[closestFirst ? rows.length - 1 - i : i]): i};
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final code = rows[closestFirst ? rows.length - 1 - i : i];
              return KeyedSubtree(key: ValueKey<String>(keyOf(code)), child: chatColumn(Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), child: item(code))));
            },
            childCount: rows.length,
            findChildIndexCallback: (k) => k is ValueKey<String> ? at[k.value] : null,
          ),
        );
      }

      return Stack(children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(isComplex: true, painter: _DotWallpaper(c.textMedium.withValues(alpha: c.isDark ? 0.07 : 0.06))))),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomScrollView(
              controller: _scroll,
              reverse: true,
              center: _centerKey,
              anchor: _anchorAt,
              slivers: [
                // newer than the anchor: grows downwards from it, nothing above moves
                if (below.isNotEmpty) sliver(below, closestFirst: true),
                SliverPadding(key: _centerKey, padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), sliver: sliver(above)),
              ],
            ),
          ),
        ),
        if (!_atLatest)
          PositionedDirectional(
            end: box.maxWidth >= 600 ? 56 : AppSpace.md, // clear of the docked assistant tab
            bottom: AppSpace.sm,
            child: ChatJumpToLatest(count: _t.newBelow, onTap: () => _toLatest(animate: true)),
          ),
      ]);
    });
  }

  String? _reasonOf(ChatConversation conv) {
    final r = AppConfig.lang == 'ar' ? conv.composerReason : conv.composerReasonEn;
    return r.isEmpty ? null : r;
  }

  Widget _composer(ChatConversation? conv) {
    if (conv == null) return const SizedBox.shrink();
    final state = conv.composer ?? ChatComposerState.open;
    if (state == ChatComposerState.requestReceived) {
      return ChatRequestDecisionBar(
        busy: _deciding,
        name: conv.title,
        reason: _reasonOf(conv),
        onAccept: () => _decide(() async {
          await _hub.acceptRequest(conv.id);
          await _t.reloadHeader();
        }),
        onDecline: () => _decide(() => _hub.declineRequest(conv.id), leave: true),
        onBlock: () => _blockRequest(conv),
      );
    }
    if (state != ChatComposerState.open) {
      return ChatComposerNotice(
        state: state,
        reason: _reasonOf(conv),
        onUnblock: state == ChatComposerState.youBlocked ? () => unblockFromThread(context, conv, () => _t.reloadHeader()) : null,
      );
    }
    return EnterSubmits.none(
      child: ChatComposerBar(
        controller: _text,
        focusNode: _focus,
        files: _files,
        enterSends: chatEnterSends,
        onChanged: _onChanged,
        onSend: _send,
        onAttach: conv.attachmentsOn ? _attach : null,
        onRemoveFile: (i) => setState(() => _files.removeAt(i)),
        replyTo: _replyTo,
        replyIsMine: _replyTo?.senderId == _hub.myId,
        onCancelReply: () => setState(() => _replyTo = null),
        hint: conv.announceOnly ? 'sc_chat_reply_hint'.tr : null,
      ),
    );
  }
}

/// Remembers its message's context while it is built, so a jump to a quote can find it.
class _Tracked extends StatefulWidget {
  const _Tracked({required this.id, required this.built, required this.child});
  final String id;
  final Map<String, BuildContext> built;
  final Widget child;

  @override
  State<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<_Tracked> {
  @override
  void initState() {
    super.initState();
    widget.built[widget.id] = context;
  }

  @override
  void didUpdateWidget(_Tracked old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      widget.built.remove(old.id);
      widget.built[widget.id] = context;
    }
  }

  @override
  void dispose() {
    widget.built.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A chat with nothing in it yet: who it is with, and a nudge.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({this.conversation});
  final ChatConversation? conversation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (conv != null) ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 72, group: conv.isGroup && conv.course?.imageUrl == null),
          if (conv != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(conv.title, textAlign: TextAlign.center, style: AppType.section(context)),
          ],
          const SizedBox(height: AppSpace.xs),
          Text('chat_start_hint'.tr, style: appText(13.5, c: c.textMedium), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({this.conversation, this.typingName, required this.showBack, this.onBack, required this.onInfo});
  final ChatConversation? conversation;
  final String? typingName;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    String sub = '';
    if (typingName != null) {
      sub = conv?.isGroup == true ? '$typingName ${'chat_is_typing'.tr}' : 'chat_typing'.tr;
    } else if (conv != null && conv.announceOnly) {
      sub = 'sc_chat_from_teacher'.tr;
    } else if (conv != null) {
      final parts = <String>[
        if (!conv.isGroup && conv.online) 'chat_online'.tr,
        if (conv.request?.pending ?? false) 'chat_request_badge'.tr,
        if (conv.isGroup && conv.memberCount != null) countText(conv.memberCount!, ar1: 'عضو واحد', ar2: 'عضوان', arFew: '{n} أعضاء', arMany: '{n} عضوًا', en1: '1 member', en: '{n} members'),
        if (!conv.isGroup && conv.child != null) '${'chat_parent_of'.tr} ${conv.child!.name.split(' ').first}',
        if (!conv.isGroup && conv.contextLine.isNotEmpty) conv.contextLine,
      ];
      sub = parts.join(' · ');
    }
    final live = typingName != null;
    final onlineNow = conv?.online == true && !(conv?.isGroup ?? false);
    return Material(
      color: c.cardBg,
      child: Container(
        height: kChatBarHeight,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Row(children: [
          if (showBack) AppBackButton(onPressed: onBack),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              onTap: conv == null ? null : onInfo,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                child: Row(children: [
                  if (conv != null) ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 42, online: conv.online, group: conv.isGroup && conv.course?.imageUrl == null),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(conv?.announceOnly == true ? 'sc_chat_ann_title'.tr.replaceAll('{course}', conv!.title) : (conv?.title ?? ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark)),
                      if (sub.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w500, c: live ? chatInk(c) : (onlineNow ? c.success : c.textMedium))),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          if (conv != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'chat_more'.tr,
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox?;
                  showChatRowActions(context, conv, inThread: true, anchor: chatEnterSends && box != null ? box.localToGlobal(Offset.zero) & box.size : null);
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _DotWallpaper extends CustomPainter {
  _DotWallpaper(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 26.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = (y / step).floor().isEven ? 0.0 : step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.3, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotWallpaper old) => old.color != color;
}

/// Opens the chat with a person, from anywhere (a course page, the parent's "Message the teacher"): the '/chat' page.
Future<void> openChatWith(BuildContext context, {required int peerId, int? courseId, int? orgId}) async {
  await AppShellNav.navigatorFor(context).pushNamed('/chat', arguments: {'peer_id': peerId, 'course_id': courseId, 'org_id': orgId});
}

ChatApi chatApi() => ChatHub.instance.api;

/// The line on top of the teacher's announcements (a learner's view of a course group, privacy D-1950): what lands
/// here and where a reply goes.
class ScAnnouncementsBanner extends StatelessWidget {
  const ScAnnouncementsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.kit.warn;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, size: AppIconSize.md, color: tone.ink),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text('sc_chat_ann_banner'.tr, style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Under a learner's own message in the announcements: it reached the teacher alone.
class ScPrivateReplyNote extends StatelessWidget {
  const ScPrivateReplyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs, bottom: AppSpace.xs),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Icon(Icons.lock_outline_rounded, size: AppIconSize.xs, color: c.textMedium),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text('sc_chat_reached_teacher_only'.tr, style: AppType.meta(context))),
      ]),
    );
  }
}
