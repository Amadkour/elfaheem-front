// lib/features/shared/chat/chat_page.dart — NextBrain Messages (D-330): the one chat design for every role.
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
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show EnterSubmits;
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

class _ChatHomePageState extends State<ChatHomePage> {
  final ChatHub _hub = ChatHub.instance;
  Timer? _presence;

  @override
  void initState() {
    super.initState();
    _hub.start();
    _hub.load();
    _heartbeat();
    _presence = Timer.periodic(const Duration(seconds: 45), (_) => _heartbeat());
    final peer = widget.startPeerId;
    if (peer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startWith(peer, widget.startCourseId, widget.startOrgId));
    } else if (widget.initialConversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.initialConversationId!));
    }
  }

  void _heartbeat() => _hub.api.presence(true).catchError((_) {});

  @override
  void dispose() {
    _presence?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final split = width >= kChatSplitFrom;
    return BasePage(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _hub,
          builder: (context, _) {
            final list = ChatListView(hub: _hub, onOpen: _open, onNewChat: _newChat, onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null);
            if (!split) return list;
            return Row(children: [
              SizedBox(width: kChatListWidth, child: list),
              const VerticalDivider(width: 1),
              Expanded(
                child: _hub.selectedId == null
                    ? const _NoChatSelected()
                    : ChatThreadView(key: ValueKey(_hub.selectedId), conversationId: _hub.selectedId!, showBack: false),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
            child: Icon(Icons.forum_rounded, size: AppIconSize.hero, color: c.primary),
          ),
          const SizedBox(height: AppSpace.md),
          Text('chat_empty_detail_title'.tr, style: c.h3),
          const SizedBox(height: AppSpace.xxs),
          Text('chat_empty_detail_body'.tr, style: appText(13, c: c.textMedium), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class ChatListView extends StatelessWidget {
  const ChatListView({super.key, required this.hub, required this.onOpen, required this.onNewChat, this.onBack});
  final ChatHub hub;
  final void Function(int id) onOpen;
  final VoidCallback onNewChat;
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
              IconButton(tooltip: 'chat_back'.tr, icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
              const SizedBox(width: AppSpace.xxs),
            ],
            Expanded(child: Text('chat_title'.tr, style: c.h2.copyWith(fontWeight: FontWeight.w700))),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
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
    if (hub.loading && hub.conversations.isEmpty) return const AppListSkeleton(items: 8);
    if (hub.error != null && hub.conversations.isEmpty) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: hub.error!, actionLabel: 'chat_retry'.tr, onAction: () => hub.load());
    }
    if (hub.conversations.isEmpty) {
      final filtered = hub.filter != 'all' || hub.search.isNotEmpty || hub.role != null || hub.courseId != null;
      return AppEmpty(
        icon: filtered ? Icons.filter_alt_off_rounded : Icons.forum_outlined,
        title: filtered ? 'chat_none_filtered'.tr : 'chat_none_title'.tr,
        message: filtered ? null : 'chat_none_body'.tr,
        actionLabel: filtered ? null : 'chat_new_chat'.tr,
        onAction: filtered ? null : onNewChat,
      );
    }
    return AppRefresh(
      onRefresh: () => hub.load(silent: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) hub.loadMore();
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.lg),
          itemCount: hub.conversations.length,
          itemBuilder: (context, i) {
            final conv = hub.conversations[i];
            return ChatConversationTile(
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

class ChatThreadPage extends StatelessWidget {
  const ChatThreadPage({super.key, required this.conversationId});
  final int conversationId;

  @override
  Widget build(BuildContext context) => BasePage(child: SafeArea(child: ChatThreadView(conversationId: conversationId)));
}

/// One open chat: the header, the messages and the composer. A subtle dot wallpaper sits behind the messages.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({super.key, required this.conversationId, this.showBack = true, this.controller});
  final int conversationId;
  final bool showBack;
  final ChatThreadController? controller;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> with WidgetsBindingObserver {
  late final ChatThreadController _t = widget.controller ?? ChatThreadController(widget.conversationId);
  final _scroll = ScrollController();
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<ChatLocalFile> _files = [];
  Timer? _saveDraft;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    WidgetsBinding.instance.addObserver(this);
    _text.text = ChatHub.instance.drafts[widget.conversationId] ?? '';
    _t.addListener(_onUpdate);
    if (_ownsController) _t.open();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _t.loadOlder();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _t.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDraft?.cancel();
    ChatHub.instance.setDraft(widget.conversationId, _text.text);
    _t.removeListener(_onUpdate);
    if (_ownsController) _t.dispose();
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _onChanged(String v) {
    setState(() {});
    _saveDraft?.cancel();
    _saveDraft = Timer(const Duration(milliseconds: 450), () => ChatHub.instance.setDraft(widget.conversationId, _text.text));
    _t.typingChanged(v.trim().isNotEmpty);
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty && _files.isEmpty) return;
    final files = List<ChatLocalFile>.from(_files);
    _text.clear();
    setState(() => _files.clear());
    ChatHub.instance.setDraft(widget.conversationId, '');
    await _t.send(text, files: files);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _focus.requestFocus();
  }

  Future<void> _attach() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return;
    final add = <ChatLocalFile>[];
    for (final f in picked.take(10 - _files.length)) {
      add.add(ChatLocalFile(name: f.name, bytes: kIsWeb ? await f.readAsBytes() : null, path: kIsWeb ? null : f.path, size: (await f.length()) ?? 0));
    }
    if (mounted) setState(() => _files.addAll(add));
  }

  final Map<int, Future<String>> _urls = {};
  Future<String> _imageUrl(ChatAttachment a) => _urls[a.id] ??= ChatHub.instance.api.attachmentLink(a.id);

  Future<void> _openAttachment(ChatAttachment a) async {
    try {
      final url = await ChatHub.instance.api.attachmentLink(a.id, inline: a.image);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = _t.conversation;
    return ColoredBox(
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ChatHeader(conversation: conv, typingName: _t.typingName, showBack: widget.showBack, onInfo: _showInfo),
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
    final myId = ChatHub.instance.myId;
    return LayoutBuilder(builder: (context, box) {
      final bubbleWidth = (box.maxWidth * 0.8).clamp(240.0, kChatBubbleMaxWidth);
      return CustomPaint(
        painter: _DotWallpaper(c.textLight.withValues(alpha: 0.05)),
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
          itemCount: msgs.length + (_t.typingName != null ? 1 : 0) + (_t.loadingOlder ? 1 : 0),
          itemBuilder: (context, i) {
            if (_t.typingName != null && i == 0) return ChatTypingBubble(name: group ? _t.typingName : null);
            final idx = i - (_t.typingName != null ? 1 : 0);
            if (idx >= msgs.length) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
            final m = msgs[idx];
            final older = idx + 1 < msgs.length ? msgs[idx + 1] : null;
            final newer = idx > 0 ? msgs[idx - 1] : null;
            final startsRun = older == null || older.senderId != m.senderId || m.createdAt.difference(older.createdAt) > const Duration(minutes: 5) || !chatSameDay(older.createdAt, m.createdAt);
            final endsRun = newer == null || newer.senderId != m.senderId || newer.createdAt.difference(m.createdAt) > const Duration(minutes: 5) || !chatSameDay(newer.createdAt, m.createdAt);
            final mine = m.senderId == myId;
            final showDate = older == null || !chatSameDay(older.createdAt, m.createdAt);
            final bubble = ChatBubble(
              message: m,
              mine: mine,
              tick: chatTickFor(m, peerReadId: group ? null : conv?.peerReadId, peerDeliveredId: group ? null : conv?.peerDeliveredId),
              showSender: group && startsRun,
              tail: endsRun,
              maxWidth: bubbleWidth,
              imageOf: _imageUrl,
              onOpenAttachment: _openAttachment,
              onLongPress: conv == null ? null : () => showChatMessageActions(context, conv, m, mine: mine),
              onRetry: m.sendState == ChatSendState.failed ? () => _t.retry(m) : null,
            );
            final row = group && !mine
                ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    SizedBox(
                      width: 34,
                      child: endsRun ? Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: AppAvatar(name: m.senderName ?? '', url: m.senderImage, size: 28)) : null,
                    ),
                    Expanded(child: bubble),
                  ])
                : bubble;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showDate) ChatDateChip(label: chatDayLabel(m.createdAt)),
              row,
            ]);
          },
        ),
      );
    });
  }

  Widget _composer(ChatConversation? conv) {
    if (conv == null) return const SizedBox.shrink();
    final state = conv.composer ?? ChatComposerState.open;
    if (state != ChatComposerState.open) {
      return ChatComposerNotice(state: state, onUnblock: state == ChatComposerState.youBlocked ? () => unblockFromThread(context, conv, () => _t.reloadHeader()) : null);
    }
    final c = context.colors;
    final canSend = _text.text.trim().isNotEmpty || _files.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (var i = 0; i < _files.length; i++) ChatPendingFileChip(name: _files[i].name, onRemove: () => setState(() => _files.removeAt(i))),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (conv.attachmentsOn)
              IconButton(tooltip: 'chat_attach'.tr, icon: Icon(Icons.attach_file_rounded, color: c.textMedium), onPressed: _attach),
            Expanded(
              child: EnterSubmits.none(
                child: Focus(
                  onKeyEvent: (node, ev) {
                    if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.enter && (kIsWeb || MediaQuery.sizeOf(context).width >= kChatSplitFrom) && !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textDirection: _text.text.isEmpty ? null : contentDirection(_text.text),
                    style: appText(14.5, w: FontWeight.w400, c: c.textDark),
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'chat_message_hint'.tr,
                      counterText: '',
                      filled: true,
                      fillColor: c.inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.primary.withValues(alpha: 0.45), width: 1.2)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            _SendButton(enabled: canSend, onTap: _send),
          ]),
        ]),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'chat_send'.tr,
      enabled: enabled,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 26,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: enabled ? c.primaryGradient : null, color: enabled ? null : c.inputBg),
          child: Icon(Icons.send_rounded, size: AppIconSize.md, color: enabled ? c.onHero : c.textLight),
        ),
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
          if (showBack) IconButton(tooltip: 'chat_back'.tr, icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
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
