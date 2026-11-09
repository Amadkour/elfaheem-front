// lib/features/shared/chat/chat_page.dart — NextBrain Messages (D-330, D-375): the one chat design for every role.
//
//   ChatHomePage(initialConversationId:, startPeerId:…)  the list; from 860 px the list and the open chat side by side,
//                                                        below that a chat opens as a pushed ChatThreadPage
//   ChatThreadView / ChatThreadPage                      one chat: header, messages, composer
//
// Kill switch `chat`. Reached through ChatEntryIcon in every role's shell and home header (route '/chat').
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_api.dart';
import 'chat_models.dart';
import 'chat_sheets.dart';
import 'chat_store.dart';
import 'chat_widgets.dart';

const kChatFeatureKey = 'chat';
const double kChatSplitFrom = 860;

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

  void _open(int id) {
    final wide = MediaQuery.sizeOf(context).width >= kChatSplitFrom;
    if (wide) {
      setState(() => _hub.selectedId = id);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(conversationId: id)));
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
    final width = MediaQuery.sizeOf(context).width;
    final split = width >= kChatSplitFrom;
    return BasePage(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _hub,
          builder: (context, _) {
            final list = ChatListView(
              hub: _hub,
              onOpen: _open,
              onNewChat: _newChat,
              onRequests: _openRequests,
              onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
            );
            if (!split) return list;
            return Row(children: [
              SizedBox(width: kChatListWidth, child: list),
              const VerticalDivider(width: 1),
              Expanded(
                child: _hub.selectedId == null
                    ? _NoChatSelected(onNewChat: _newChat)
                    : ChatThreadView(
                        key: ValueKey(_hub.selectedId),
                        conversationId: _hub.selectedId!,
                        showBack: false,
                        onLeave: () => setState(() => _hub.selectedId = null),
                      ),
              ),
            ]);
          },
        ),
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
      color: c.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              child: Icon(Icons.forum_rounded, size: AppIconSize.hero, color: c.primary),
            ),
            const SizedBox(height: AppSpace.md),
            Text('chat_empty_detail_title'.tr, style: c.h3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text('chat_empty_detail_body'.tr, style: appText(13.5, c: c.textMedium, h: 1.4), textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppSpace.md),
            AppButton(label: 'chat_new_chat'.tr, icon: Icons.edit_outlined, onPressed: onNewChat),
          ]),
        ),
      ),
    );
  }
}

/// The inbox: requests first, then what needs the person, then everything else.
class ChatListView extends StatelessWidget {
  const ChatListView({super.key, required this.hub, required this.onOpen, required this.onNewChat, this.onRequests, this.onBack});
  final ChatHub hub;
  final void Function(int id) onOpen;
  final VoidCallback onNewChat;
  final VoidCallback? onRequests;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filterChips = <Widget>[
      ChatFilterChip(label: 'chat_filter_all'.tr, selected: hub.filter == 'all' && hub.role == null && hub.courseId == null, onTap: () => hub.applyFilters(filter: 'all', clearCourse: true, clearRole: true)),
      ChatFilterChip(label: 'chat_filter_unread'.tr, selected: hub.filter == 'unread', onTap: () => hub.applyFilters(filter: hub.filter == 'unread' ? 'all' : 'unread')),
      ChatFilterChip(label: 'chat_filter_groups'.tr, icon: Icons.groups_rounded, selected: hub.filter == 'groups', onTap: () => hub.applyFilters(filter: hub.filter == 'groups' ? 'all' : 'groups')),
      ChatFilterChip(label: 'chat_filter_pinned'.tr, icon: Icons.push_pin_outlined, selected: hub.filter == 'pinned', onTap: () => hub.applyFilters(filter: hub.filter == 'pinned' ? 'all' : 'pinned')),
      for (final r in const ['teacher', 'parent', 'student'])
        if (hub.filterRoles.contains(r)) ChatFilterChip(label: 'chat_role_$r'.tr, selected: hub.role == r, onTap: () => hub.applyFilters(role: hub.role == r ? null : r, clearRole: hub.role == r)),
      for (final course in hub.filterCourses)
        ChatFilterChip(label: course.label, icon: Icons.menu_book_rounded, selected: hub.courseId == course.id, onTap: () => hub.applyFilters(courseId: hub.courseId == course.id ? null : course.id, clearCourse: hub.courseId == course.id)),
    ];
    final showMoreMenu = !AppConfig.disableList.contains('chat.blocking');
    return Material(
      color: c.cardBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.xs),
          child: Row(children: [
            if (onBack != null) ...[
              AppBackButton(onPressed: onBack),
              const SizedBox(width: AppSpace.xxs),
            ],
            Expanded(child: Text('chat_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.h2.copyWith(fontWeight: FontWeight.w700))),
            if (showMoreMenu)
              IconButton(
                tooltip: 'chat_blocked_people'.tr,
                icon: Icon(Icons.shield_outlined, color: c.textMedium),
                onPressed: () => AppShellNav.navigatorFor(context).pushNamed('/chat/blocks'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: AppIconButton(icon: Icons.edit_square, tooltip: 'chat_new_chat'.tr, onPressed: onNewChat),
            ),
          ]),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: AppConnectivity.instance.online,
          builder: (_, online, _) => online ? const SizedBox.shrink() : const ChatOfflineStrip(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs),
          child: AppSearchField(hint: 'chat_search_hint'.tr, dense: true, onChanged: (q) => hub.applyFilters(search: q)),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: filterChips.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
            itemBuilder: (_, i) => filterChips[i],
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Expanded(child: _rows(context)),
      ]),
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
    final sections = chatInboxSections(hub.conversations, plain: hub.plainList);
    final entries = <Object>[
      if (hub.requestCount > 0 && !filtered) 'requests',
      if (sections.attention.isNotEmpty) ...[const _Label('chat_section_new'), ...sections.attention],
      if (sections.attention.isNotEmpty && sections.rest.isNotEmpty) const _Label('chat_section_earlier'),
      ...sections.rest,
    ];
    return AppRefresh(
      onRefresh: () => hub.load(silent: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 300) hub.loadMore();
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.lg),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            if (e == 'requests') return ChatRequestsRow(count: hub.requestCount, onTap: () => onRequests?.call());
            if (e is _Label) return ChatSectionLabel(label: e.key.tr);
            final conv = e as ChatConversation;
            return ChatConversationTile(
              key: ValueKey('chat-row-${conv.id}'),
              conversation: conv,
              myId: hub.myId,
              selected: hub.selectedId == conv.id,
              typingName: hub.typing[conv.id],
              draft: hub.drafts[conv.id],
              onTap: () => onOpen(conv.id),
              onMenu: () => showChatRowActions(context, conv),
            );
          },
        ),
      ),
    );
  }
}

class _Label {
  const _Label(this.key);
  final String key;
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

class ChatThreadPage extends StatelessWidget {
  const ChatThreadPage({super.key, required this.conversationId});
  final int conversationId;

  @override
  Widget build(BuildContext context) => BasePage(child: SafeArea(child: ChatThreadView(conversationId: conversationId)));
}

/// One open chat: the header, the messages and the composer. A subtle dot wallpaper sits behind the messages.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({super.key, required this.conversationId, this.showBack = true, this.controller, this.onLeave});
  final int conversationId;
  final bool showBack;
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

  ChatHub get _hub => _t.hub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.text = _hub.drafts[widget.conversationId] ?? '';
    _newestKey = _t.messages.firstOrNull?.clientId;
    _t.addListener(_onUpdate);
    if (_ownsController) {
      _t.open().then((_) => _applyDraft());
    }
    _scroll.addListener(_onScroll);
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
    if (_draftTouched) _hub.setDraft(widget.conversationId, _text.text);
    _t.removeListener(_onUpdate);
    if (_ownsController) _hub.release(_t);
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onUpdate() {
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
    setState(() => _anchorKey = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
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

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty && _files.isEmpty) return;
    final files = List<ChatLocalFile>.from(_files);
    _saveDraft?.cancel();
    _text.clear();
    _draftTouched = false;
    setState(() => _files.clear());
    _hub.setDraft(widget.conversationId, '');
    _t.send(text, files: files);
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

  Future<void> _openAttachment(ChatAttachment a) async {
    try {
      final url = await _hub.api.attachmentLink(a.id, inline: a.image);
      if (a.image && mounted) {
        showChatImage(context, url, a.name);
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ChatHeader(conversation: conv, typingName: _t.typingName, showBack: widget.showBack, onInfo: _showInfo),
        ValueListenableBuilder<bool>(
          valueListenable: AppConnectivity.instance.online,
          builder: (_, online, _) => online ? const SizedBox.shrink() : const ChatOfflineStrip(),
        ),
        Expanded(child: _body(c)),
        _composer(conv),
      ]),
    );
  }

  Widget _body(ThemeConfigProvider c) {
    if (_t.loading && _t.messages.isEmpty) {
      return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 8, withAvatar: false));
    }
    if (_t.error != null && _t.messages.isEmpty && _t.conversation == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: _t.error!);
    }
    if (_t.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.waving_hand_outlined, size: AppIconSize.hero, color: c.textLight),
            const SizedBox(height: AppSpace.sm),
            Text('chat_start_hint'.tr, style: appText(13.5, c: c.textMedium), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final msgs = _t.messages;
    final conv = _t.conversation;
    final group = conv?.isGroup ?? false;
    final myId = _hub.myId;
    final showTyping = _t.typingName != null && _atLatest;
    // what the list draws, bottom to top: the typing dots, the messages, "loading older"
    final items = <int>[if (showTyping) -1, for (var i = 0; i < msgs.length; i++) i, if (_t.loadingOlder) -2];
    final anchorIdx = _anchorKey == null ? -1 : items.indexWhere((x) => x >= 0 && msgs[x].clientId == _anchorKey);
    final below = anchorIdx > 0 ? items.sublist(0, anchorIdx) : const <int>[];
    final above = anchorIdx > 0 ? items.sublist(anchorIdx) : items;

    return LayoutBuilder(builder: (context, box) {
      final column = box.maxWidth > kChatColumnMaxWidth ? kChatColumnMaxWidth : box.maxWidth;
      final bubbleWidth = (column * 0.78).clamp(240.0, kChatBubbleMaxWidth);
      Widget item(int code) {
        if (code == -1) return ChatTypingBubble(name: group ? _t.typingName : null);
        if (code == -2) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        final m = msgs[code];
        final older = code + 1 < msgs.length ? msgs[code + 1] : null;
        final newer = code > 0 ? msgs[code - 1] : null;
        bool together(ChatMessage a, ChatMessage b) => a.senderId == b.senderId && b.createdAt.difference(a.createdAt) <= const Duration(minutes: 5) && chatSameDay(a.createdAt, b.createdAt);
        final runStart = older == null || !together(older, m);
        final runEnd = newer == null || !together(m, newer);
        final mine = m.senderId == myId;
        final showDate = older == null || !chatSameDay(older.createdAt, m.createdAt);
        final failed = m.sendState == ChatSendState.failed;
        final bubble = ChatBubble(
          message: m,
          mine: mine,
          tick: chatTickFor(m, peerReadId: group ? null : conv?.peerReadId, peerDeliveredId: group ? null : conv?.peerDeliveredId),
          showSender: group && runStart,
          runStart: runStart,
          runEnd: runEnd,
          maxWidth: bubbleWidth,
          imageOf: _imageUrl,
          onOpenAttachment: _openAttachment,
          onLongPress: conv == null || m.id == null ? null : () => showChatMessageActions(context, conv, m, mine: mine),
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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showDate) ChatDateChip(label: chatDayLabel(m.createdAt)),
          if (_t.firstUnreadKey == m.clientId) const ChatUnreadDivider(),
          row,
        ]);
      }

      Widget sliver(List<int> rows, {bool closestFirst = false}) => SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => chatColumn(item(closestFirst ? rows[rows.length - 1 - i] : rows[i])),
              childCount: rows.length,
            ),
          );

      return Stack(children: [
        CustomPaint(
          painter: _DotWallpaper(c.textLight.withValues(alpha: 0.05)),
          child: CustomScrollView(
            controller: _scroll,
            reverse: true,
            center: _centerKey,
            slivers: [
              // newer than the anchor: grows downwards from it, nothing above moves
              if (below.isNotEmpty) sliver(below, closestFirst: true),
              SliverPadding(key: _centerKey, padding: const EdgeInsets.all(AppSpace.sm), sliver: sliver(above)),
            ],
          ),
        ),
        if (!_atLatest)
          PositionedDirectional(
            end: AppSpace.md,
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
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({this.conversation, this.typingName, required this.showBack, required this.onInfo});
  final ChatConversation? conversation;
  final String? typingName;
  final bool showBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    String sub = '';
    if (typingName != null) {
      sub = conv?.isGroup == true ? '$typingName ${'chat_is_typing'.tr}' : 'chat_typing'.tr;
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
    return Material(
      color: c.cardBg,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
        child: Row(children: [
          if (showBack) const AppBackButton(),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: conv == null ? null : onInfo,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
                child: Row(children: [
                  if (conv != null) ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 42, online: conv.online, group: conv.isGroup && conv.course?.imageUrl == null),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(conv?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15.5, w: FontWeight.w700, c: c.textDark)),
                      if (sub.isNotEmpty)
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w500, c: typingName != null || conv?.online == true ? c.success : c.textMedium)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          if (conv != null)
            IconButton(
              tooltip: 'chat_more'.tr,
              icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
              onPressed: () => showChatRowActions(context, conv, inThread: true),
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
