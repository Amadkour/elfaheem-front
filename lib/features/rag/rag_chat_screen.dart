// The assistant's conversation (Phase 7, D-022; premium assistant D-012): ask the app's pages, the organization's
// rules or the course's documents and get an answer written from them with its sources. `app: true` is the app
// assistant: the platform's own documents for every user; with `orgId` too it is the app assistant opened inside
// an organization (that organization's library and rules as well). [RagChatView] is the conversation itself
// (history, answers, starter prompts, the question box) without a page around it: [RagChatScreen] puts it in a
// page, the floating app assistant (app_assistant.dart) in its pop-up. The presentational parts — [RagAnswerCard],
// [RagAnswerBody], [RagStageTrail], [RagPartialAnswer], [RagStarterPrompts] — take plain values and run under the
// layout harness; the view owns the API calls and the polling. While the model writes, the pending card shows the
// draft ([RagAnswer.provisional], Track E.8) under the stage trail in a muted style with a typing caret (steady under
// reduced motion), then the final answer with its sources takes its place.
//
// Chat sessions (Track E.5): the view asks `GET /conversations` first. On a server that has them it keeps the
// current conversation ([RagChatViewState.newChat] starts a clean one, created lazily on the first question;
// [showSessions] lists them — a bottom sheet on phones, a side panel from [Breakpoints.desktop]; reopening loads
// that conversation's messages oldest first, "Load earlier" pages back with `has_more`); on an older server
// (a bare 404 / 405) it keeps the flat history as before. The client sends only `conversation_id`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/rag/chat/rag_action_open.dart';
import 'package:flutter_education_app/features/rag/chat/rag_answer_extras.dart';
import 'package:flutter_education_app/features/rag/chat/rag_chat_parts.dart';
import 'package:flutter_education_app/features/rag/chat/rag_payload.dart';
import 'package:flutter_education_app/core/api_error_text.dart' show featureDisabledText;
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_education_app/features/rag/rag_chat_sessions.dart';
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_learning.dart';
import 'package:flutter_education_app/features/rag/rag_library_screen.dart';

export 'package:flutter_education_app/features/rag/rag_chat_sessions.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen(
      {super.key,
      this.orgId,
      this.courseId,
      this.app = false,
      this.title,
      this.conversationId,
      this.resumeLatest = true,
      this.draft,
      this.onClosed});
  final int? orgId;
  final int? courseId;
  final bool app;
  final String? title;

  /// The conversation to open (the pop-up's current one when it expands); null = the latest if [resumeLatest], else
  /// a new chat (the pop-up expanding on a new chat passes false: the new chat stays new).
  final int? conversationId;
  final bool resumeLatest;

  /// Typed into the box, not sent (the pop-up's unsent question when it expands).
  final String? draft;

  /// The page is leaving: the conversation it ended on (null = a new chat) and the unsent text in its box — the
  /// pop-up picks both up again.
  final void Function(int? conversationId, String draft)? onClosed;

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  final _chat = GlobalKey<RagChatViewState>();
  bool _manager = false; // library managers get the Library action (from the documents list: manager: true)
  bool _sessions = false; // the server has chat sessions: New chat + Chats actions
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final page = _page(context);
    if (widget.onClosed == null) return page;
    // read while the chat is still mounted (its state is gone by the time this page is disposed)
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        final chat = _chat.currentState;
        if (!didPop || _closed || chat == null) return;
        _closed = true;
        widget.onClosed!(chat.conversationId, chat.draftText);
      },
      child: page,
    );
  }

  Widget _page(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.assistant'),
      appBar: ScreenAppBar(helpPageId: 'rag.chat', title: widget.title ?? (widget.app ? t('مساعد التطبيق', 'App assistant') : t('مساعد المستندات', 'Documents assistant')),
          actions: [
            if (_sessions) IconButton(tooltip: 'rag_new_chat'.tr, icon: const Icon(Icons.add_comment_outlined), onPressed: () => _chat.currentState?.newChat()),
            if (_sessions) IconButton(tooltip: 'rag_chats'.tr, icon: const Icon(Icons.history_rounded), onPressed: () => _chat.currentState?.showSessions()),
            if (_manager)
              IconButton(
                  tooltip: t('مكتبة المستندات', 'Documents library'),
                  icon: const Icon(Icons.folder_copy_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RagLibraryScreen(orgId: widget.app ? null : widget.orgId, courseId: widget.courseId, app: widget.app)))),
            IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: () => _chat.currentState?.refresh()),
            if (widget.orgId != null && !widget.app) const ContextExitButton(),
          ]),
      child: RagChatView(
          key: _chat,
          orgId: widget.orgId,
          courseId: widget.courseId,
          app: widget.app,
          initialConversationId: widget.conversationId,
          resumeLatest: widget.resumeLatest,
          initialDraft: widget.draft,
          onSessionsSupported: (s) {
            if (s != _sessions) setState(() => _sessions = s);
          },
          onManager: (m) {
            if (m != _manager) setState(() => _manager = m);
          }),
    );
  }
}

/// The conversation: the caller's earlier questions with their answers, then the question box. Fills the height it
/// is given (it must be bounded: an Expanded, a page body, a sized pop-up).
class RagChatView extends StatefulWidget {
  const RagChatView({
    super.key,
    this.orgId,
    this.courseId,
    this.app = false,
    this.onManager,
    this.compact = false,
    this.api,
    this.contextLabel,
    this.initialConversationId,
    this.resumeLatest = true,
    this.onConversationChanged,
    this.onSessionsSupported,
    this.onNavigate,
    this.learning,
    this.initialDraft,
  });
  final int? orgId;
  final int? courseId;
  final bool app;

  /// Whether the caller manages this library (the documents list answers `manager: true`).
  final ValueChanged<bool>? onManager;

  /// A narrow pop-up: tighter padding.
  final bool compact;
  final RagApi? api;

  /// Shown in the banner: where the assistant reads from (the organization's name inside an organization).
  final String? contextLabel;

  /// The conversation to open first (Track E.5); when null, the latest one if [resumeLatest], else a new chat.
  final int? initialConversationId;
  final bool resumeLatest;

  /// The current conversation changed (null = a new chat not created yet): the floating host remembers it.
  final ValueChanged<int?>? onConversationChanged;

  /// Whether the server has chat sessions (after the first call): the page shows New chat / Chats then.
  final ValueChanged<bool>? onSessionsSupported;

  /// Called before a citation's deep link opens a page (the pop-up closes).
  final VoidCallback? onNavigate;

  /// Track F: the vote with its reason and the implicit signals (citation opened, deep link, contact support).
  final LearningSignals? learning;

  /// Typed into the box at the start, not sent (the pop-up's unsent question when it expands to the full page).
  final String? initialDraft;

  @override
  State<RagChatView> createState() => RagChatViewState();
}

class RagChatViewState extends State<RagChatView> {
  late final RagApi _api = widget.api ?? RagApi();
  late final LearningSignals _learn = widget.learning ?? LearningSignals.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<RagAnswer> _items = [];

  /// How many of [_items] (the oldest) are folded away (N6): an older server's flat history that ended on a failure
  /// opens on the starter questions, with "Earlier questions" to unfold them.
  int _hiddenBefore = 0;
  List<String>? _starters; // from the server (questions the library answers); null = the built-in list
  bool _loading = true;
  bool _sending = false;

  /// Answers the worker never finished (M16): drawn as a calm error with Retry instead of a stage trail forever.
  final Set<int> _stalled = {};

  /// Unfinished answers reopened from the history that this view is following.
  final Set<int> _following = {};

  /// The chat on screen was opened by itself (the latest conversation, the flat history) and the person has not
  /// asked or picked anything since (N6): a reopened question that gives up then yields to a new chat.
  bool _untouched = false;
  String? _error;

  // chat sessions (Track E.5)
  bool? _sessions; // null = not asked yet · true = the server has conversations · false = older server (flat history)
  final List<RagConversation> _convs = [];
  int? _retentionDays;
  RagConversation? _current; // null = a new chat, created on the first question
  bool _hasMore = false, _loadingMore = false, _convsLoading = false;
  bool _panel = true; // the side panel on a wide view (the Chats action toggles it)

  RagContext get _ctx => ragContextOf(app: widget.app, orgId: widget.orgId);

  /// The open conversation's id (null = a new chat).
  int? get conversationId => _current?.id;

  /// The unsent text in the box.
  String get draftText => _input.text;

  /// Takes the unsent text out of the box (the pop-up expanding hands it to the full page).
  String takeDraft() {
    final text = _input.text;
    if (text.isNotEmpty) _input.clear();
    return text;
  }

  /// Back from the full page (the pop-up): shows the conversation the page ended on ([conversationId], null = a new
  /// chat) with its latest messages, and puts the page's unsent [draft] back in the box. Counts as picked by the
  /// person (never swapped for a new chat by itself, N6).
  Future<void> resumeFrom(int? conversationId, String draft) async {
    if (!mounted) return;
    _setDraft(draft);
    if (_sessions != true) {
      if (_sessions == false) await _history();
      return;
    }
    await _loadConversations();
    if (!mounted) return;
    final c = conversationId == null ? null : _convs.where((x) => x.id == conversationId).firstOrNull;
    if (c == null) {
      newChat();
    } else {
      await openConversation(c);
    }
  }

  void _setDraft(String text) {
    if (text == _input.text) return;
    setState(() {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    if (draft != null && draft.isNotEmpty) {
      _input.text = draft;
      _input.selection = TextSelection.collapsed(offset: draft.length);
    }
    _boot();
    _loadStarters();
    if (widget.onManager != null) _checkManager();
  }

  /// Chat sessions when the server has them (then the first conversation to show), else the flat history.
  Future<void> _boot() async {
    final r = await _api.conversations(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted) return;
    if (!ragSessionsSupported(r)) {
      _sessions = false;
      widget.onSessionsSupported?.call(false);
      await _history(opening: true);
      return;
    }
    _sessions = true;
    widget.onSessionsSupported?.call(true);
    if (!r.ok) {
      setState(() {
        _loading = false;
        _error = ragOrgBlocked(r.code) ? ragChatResultText(r) : ragCodeText(r.code, r.message);
      });
      return;
    }
    _convs..clear()..addAll(RagApi.conversationItems(r));
    _retentionDays = RagApi.retentionDays(r);
    RagConversation? open;
    final want = _draftFresh ? null : widget.initialConversationId;
    if (want != null) open = _convs.where((c) => c.id == want).firstOrNull;
    if (open == null && want == null && widget.resumeLatest && !_draftFresh) {
      // N6: an old conversation is not reopened by itself — the assistant starts on a new chat (it is under Chats)
      final latest = _convs.firstOrNull;
      if (latest != null && ragResumeConversation(latest, DateTime.now().toUtc())) open = latest;
    }
    _draftFresh = false;
    if (open != null) {
      await openConversation(open, resumed: want == null);
    } else {
      setState(() => _loading = false);
      widget.onConversationChanged?.call(null);
    }
  }

  Future<void> _loadConversations() async {
    if (_sessions != true) return;
    setState(() => _convsLoading = true);
    final r = await _api.conversations(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted) return;
    setState(() {
      _convsLoading = false;
      if (r.ok) {
        _convs..clear()..addAll(RagApi.conversationItems(r));
        _retentionDays = RagApi.retentionDays(r) ?? _retentionDays;
      }
    });
  }

  bool _draftFresh = false; // a question was handed in before the conversations loaded: start a new chat, not the latest

  /// Types [text] into the box (not sent) on a new chat when the server has chat sessions — "Ask about this page"
  /// (AppAssistant.ask). Before the conversations have loaded, the boot opens a new chat instead of the latest one.
  void draft(String text) {
    if (_sessions == true) {
      newChat();
    } else if (_sessions == null) {
      _draftFresh = true;
    }
    setState(() {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  /// A clean conversation: nothing shown, no memory; it is created on the server with the first question.
  void newChat() {
    if (_sessions != true) return;
    _untouched = false;
    setState(() {
      _current = null;
      _items.clear();
      _hiddenBefore = 0;
      _error = null;
      _hasMore = false;
      _loading = false;
    });
    widget.onConversationChanged?.call(null);
  }

  /// Reopens [c]: its messages oldest first (the first page; "Load earlier" pages back). [resumed]: opened by itself
  /// (the latest conversation), not picked — one that ends on a failure then gives way to a new chat (N6).
  Future<void> openConversation(RagConversation c, {bool resumed = false}) async {
    _untouched = resumed;
    setState(() {
      _current = c;
      _items.clear();
      _hiddenBefore = 0;
      _error = null;
      _hasMore = false;
      _loading = true;
    });
    widget.onConversationChanged?.call(c.id);
    final r = await _api.messages(c.id);
    if (!mounted || _current?.id != c.id) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items..clear()..addAll(RagApi.items(r));
        _hasMore = RagApi.hasMore(r);
      } else if (r.code == 'conversation_not_found' || r.code == 'not_owner') {
        _convs.removeWhere((x) => x.id == c.id);
        _current = null;
        _error = ragCodeText(r.code, r.message);
      } else {
        _error = ragChatResultText(r);
      }
    });
    if (_current == null) widget.onConversationChanged?.call(null);
    // N6: the first thing the person sees is never a failed / abandoned answer — a new chat with the starter
    // questions instead; the conversation stays under Chats
    if (resumed && r.ok && ragOpensOnFailure(_items, DateTime.now().toUtc(), askedAt: c.lastAt)) {
      newChat();
      _noticeSwapped();
      return;
    }
    _followUnfinished();
    _toEnd();
  }

  /// The history may hold questions still unfinished (asked just before the chat closed, or abandoned by a stopped
  /// worker): an old one is shown as stalled at once, a recent one is followed for the patience it has left.
  void _followUnfinished() {
    final now = DateTime.now().toUtc();
    final stale = <int>[];
    for (final a in _items) {
      if (a.done || _following.contains(a.id) || _stalled.contains(a.id)) continue;
      if (ragAnswerStalled(a, now)) {
        stale.add(a.id);
        continue;
      }
      _following.add(a.id);
      unawaited(_follow(a.id, ragWaitLeft(a, now)));
    }
    if (stale.isNotEmpty) setState(() => _stalled.addAll(stale));
  }

  Future<void> _follow(int id, Duration timeout) async {
    final clock = Stopwatch()..start();
    final r = await _api.waitFor(id, timeout: timeout, onUpdate: (a) {
      if (!mounted) return;
      final i = _items.indexWhere((x) => x.id == a.id);
      if (i < 0 || !ragAnswerChanged(_items[i], a)) return;
      setState(() => _items[i] = a);
    });
    _following.remove(id);
    if (!mounted) return;
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    setState(() {
      if (r.ok) _items[i] = RagAnswer.fromJson(r.map);
      // given up on only when it is really past its patience (or gone): a passing poll failure is not a failure
      if (ragGivesUp(_items[i], r, DateTime.now().toUtc(), timedOut: clock.elapsed >= timeout)) _stalled.add(id);
    });
    // N6: a reopened question that gave up before the person did anything is not what the assistant opens on
    if (_untouched && _items.last.id == id) _startFreshIfFailed();
  }

  /// The pop-up was opened again (N6): a chat the assistant opened BY ITSELF (the latest conversation, never touched
  /// since) that ends on a failure gives way to a new chat with the starter questions (it stays under Chats). A chat
  /// the person started, asked in or picked stays as it is, its failed answer with Retry; nothing changes while a
  /// question is being sent or the chat is loading.
  void reopened() {
    if (!mounted || _sending || _loading || !_untouched) return;
    _startFreshIfFailed();
  }

  void _startFreshIfFailed() {
    final shown = _items.sublist(_hiddenBefore.clamp(0, _items.length));
    if (!ragShowsFailure(shown, _stalled)) return;
    if (_sessions == true) {
      newChat();
      _noticeSwapped();
    } else {
      setState(() => _hiddenBefore = _items.length); // an older server: folded behind "Earlier questions"
    }
  }

  /// After a swap for a new chat (N6): the person is told where the previous chat went, with Chats one tap away.
  /// Only while the chat is on screen (a closed pop-up keeps its tickers off): a notice about a hidden chat would
  /// make no sense.
  void _noticeSwapped() {
    if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) return;
    showAppNotice('rag_chat_moved_to_chats'.tr,
        icon: Icons.history_rounded, actionLabel: 'rag_chats'.tr, onAction: showSessions);
  }

  /// Retry on a stalled answer: the same question again, as a new one.
  void _retry(RagAnswer a) {
    if (_sending) return;
    setState(() {
      _items.removeWhere((x) => x.id == a.id);
      _stalled.remove(a.id);
    });
    send(a.question);
  }

  Future<void> _loadEarlier() async {
    final c = _current;
    if (c == null || _loadingMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    final r = await _api.messages(c.id, before: _items.first.id);
    if (!mounted || _current?.id != c.id) return;
    setState(() {
      _loadingMore = false;
      if (r.ok) {
        final older = RagApi.items(r).where((a) => !_items.any((x) => x.id == a.id)).toList();
        _items.insertAll(0, older);
        _hasMore = RagApi.hasMore(r);
      }
    });
  }

  /// The conversations list: a bottom sheet on a phone, the side panel toggled on a wide view.
  Future<void> showSessions() async {
    if (_sessions != true) return;
    final wide = _wide(context);
    if (wide) {
      setState(() => _panel = !_panel);
      if (_panel) await _loadConversations();
      return;
    }
    await _loadConversations();
    if (!mounted) return;
    await showAppSheet<void>(context, mode: AppSheetMode.side, (ctx) => RagSessionsPanel(
          items: _convs,
          currentId: _current?.id,
          retentionDays: _retentionDays,
          loading: _convsLoading,
          onNew: () {
            Navigator.of(ctx).pop();
            newChat();
          },
          onOpen: (c) {
            Navigator.of(ctx).pop();
            if (c.id != _current?.id) openConversation(c);
          },
          onRename: (c) {
            Navigator.of(ctx).pop();
            _rename(c);
          },
          onDelete: (c) {
            Navigator.of(ctx).pop();
            _delete(c);
          },
        ));
  }

  bool _wide(BuildContext context) => !widget.compact && MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

  Future<void> _rename(RagConversation c) async {
    final title = await RagRenameDialog.show(context, c.displayTitle);
    if (title == null || !mounted || title == c.title) return;
    final r = await _api.renameConversation(c.id, title);
    if (!mounted) return;
    if (!r.ok) {
      appToast(ragCodeText(r.code, r.message), error: true);
      return;
    }
    setState(() {
      final renamed = c.copyWith(title: title);
      final i = _convs.indexWhere((x) => x.id == c.id);
      if (i >= 0) _convs[i] = renamed;
      if (_current?.id == c.id) _current = renamed;
    });
    appToast('rag_chat_saved'.tr);
  }

  Future<void> _delete(RagConversation c) async {
    if (!await appConfirm(context, message: 'rag_chat_delete_confirm'.tr, danger: true, confirmLabel: 'rag_chat_delete'.tr)) return;
    if (!mounted) return;
    final r = await _api.deleteConversation(c.id);
    if (!mounted) return;
    if (!r.ok && r.code != 'conversation_not_found') {
      appToast(ragCodeText(r.code, r.message), error: true);
      return;
    }
    setState(() => _convs.removeWhere((x) => x.id == c.id));
    if (_current?.id == c.id) newChat();
    appToast('rag_chat_deleted'.tr);
  }

  /// The side list reflects the open conversation's new question.
  void _touchCurrent() {
    final c = _current;
    if (c == null) return;
    final i = _convs.indexWhere((x) => x.id == c.id);
    final touched = c.copyWith(turns: c.turns + 1, lastAt: DateTime.now().toUtc());
    if (i >= 0) _convs.removeAt(i);
    _convs.insert(0, touched);
    _current = touched;
  }

  Future<void> _loadStarters() async {
    final r = await _api.starters(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted || !r.ok) return;
    final qs = ragStartersFrom(r.map);
    if (qs.isNotEmpty) setState(() => _starters = qs);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reloads the history (the page's Refresh action): the open conversation, else the flat history.
  void refresh() {
    setState(() => _error = null);
    if (_sessions == true) {
      _loadConversations();
      final c = _current;
      if (c != null) openConversation(c);
      return;
    }
    _history();
  }

  /// The flat history (an older server). [opening]: the view's first load — when it ends on a failure (N6) the
  /// questions are folded away behind "Earlier questions" and the starter questions show.
  Future<void> _history({bool opening = false}) async {
    final r = await _api.history(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted) return;
    if (opening) _untouched = true;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items..clear()..addAll(RagApi.items(r).reversed);
        final fold = (opening || _hiddenBefore > 0) && ragOpensOnFailure(_items, DateTime.now().toUtc());
        _hiddenBefore = fold ? _items.length : 0;
      }
      if (r.unavailable) _error = t('المساعد غير متاح بعد على هذا الخادم', 'The assistant is not available on this server yet');
      if (!r.ok && ragOrgBlocked(r.code)) _error = ragChatResultText(r); // suspended / deactivated / switched off
    });
    _followUnfinished();
    _toEnd();
  }

  Future<void> _checkManager() async {
    final r = await RagLibraryApi().list(orgId: widget.app ? null : widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted || !r.ok) return;
    widget.onManager?.call(RagLibrary.fromJson(r.map).manager);
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  /// Sends [text] (a typed question, a starter prompt or a follow-up).
  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending) return;
    _untouched = false;
    setState(() { _sending = true; _error = null; });
    // a new chat is created on the server with its first question (its title from that question)
    if (_sessions == true && _current == null) {
      final c = await _api.createConversation(orgId: widget.orgId, courseId: widget.courseId, app: widget.app, title: conversationTitleFrom(q));
      if (!mounted) return;
      if (c.ok) {
        final conv = RagConversation.fromJson(c.map);
        setState(() {
          _current = conv;
          _convs.insert(0, conv);
        });
        widget.onConversationChanged?.call(conv.id);
      } else if (c.unavailable) {
        _sessions = false; // the routes went away (a rollback): back to the flat history
        widget.onSessionsSupported?.call(false);
      } else {
        setState(() { _sending = false; _error = ragChatResultText(c); });
        return;
      }
    }
    final conversation = _current;
    final r = await _api.ask(q, orgId: widget.orgId, courseId: widget.courseId, app: widget.app, conversationId: conversation?.id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _sending = false; _error = ragChatResultText(r); });
      return;
    }
    _input.clear();
    final pending = RagAnswer.fromJson(r.map);
    if (_current?.id != conversation?.id) {
      setState(() => _sending = false); // the person moved to another chat meanwhile (the question is in the other)
      return;
    }
    setState(() {
      _items.add(pending);
      _touchCurrent();
    });
    _toEnd();
    final clock = Stopwatch()..start();
    final done = await _api.waitForLive(pending.id, r.map, onUpdate: (a) {
      if (!mounted) return;
      final i = _items.indexWhere((x) => x.id == a.id);
      if (i < 0 || !ragAnswerChanged(_items[i], a)) return;
      final first = a.provisional && !_items[i].provisional;
      setState(() => _items[i] = a);
      if (first) _toEnd(); // the draft starts: keep it in view
    });
    if (!mounted) return;
    setState(() {
      _sending = false;
      final i = _items.indexWhere((a) => a.id == pending.id);
      if (done.ok && i >= 0) _items[i] = RagAnswer.fromJson(done.map);
      // no answer within its patience (or the question is gone): the card turns into a calm error with Retry (M16);
      // a poll that failed in passing on the way never does
      final now = DateTime.now().toUtc();
      if (ragGivesUp(i >= 0 ? _items[i] : pending, done, now, timedOut: clock.elapsed >= ragAnswerPatience)) _stalled.add(pending.id);
    });
    _toEnd();
  }

  /// Thumbs up sends at once; thumbs down first asks why and offers a comment (the sheet; Skip or dismiss = none).
  /// Track F: the vote goes to POST /learning/feedback; an older server gets the old rating call, the reason folded
  /// into the comment.
  Future<void> _rate(RagAnswer a, bool helpful) async {
    String? reason, comment;
    if (!helpful) {
      final v = await showAppSheet<RagDownVote>(context, (_) => RagRatingCommentSheet(reasons: _learn.supported));
      if (!mounted) return;
      reason = v?.reason;
      comment = v?.commentOrNull;
    }
    if (_learn.supported) {
      final r = await _learn.api.feedback(chatVoteBody(a.id, helpful: helpful, reason: reason, comment: comment));
      _learn.note(r);
      if (!mounted) return;
      if (r.ok) return setState(() => _setHelpful(a.id, helpful));
      if (!learningOlderServer(r)) return; // a real refusal: as before, the rating is simply not kept
    }
    final r = await _api.rate(a.id, helpful: helpful, comment: legacyFeedbackComment(reason, comment));
    if (!mounted || !r.ok) return;
    setState(() {
      final i = _items.indexWhere((x) => x.id == a.id);
      if (i >= 0) _items[i] = RagAnswer.fromJson(r.map);
    });
  }

  void _setHelpful(int id, bool helpful) {
    final i = _items.indexWhere((x) => x.id == id);
    if (i >= 0) _items[i] = ragAnswerRated(_items[i], helpful);
  }

  /// "Contact support" under an answer that found nothing: the signal, then the help center (the pop-up closes).
  void _support(RagAnswer a) {
    _learn.signal(a.id, 'chat_support');
    widget.onNavigate?.call();
    AppNavigator.openModule('support');
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat(context);
    if (_sessions != true || !_panel || !_wide(context)) return chat;
    final c = context.colors;
    // a wide window: the conversations beside the chat
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 300,
        child: DecoratedBox(
          decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: c.divider))),
          child: RagSessionsPanel(
              items: _convs,
              currentId: _current?.id,
              retentionDays: _retentionDays,
              loading: _convsLoading,
              onNew: newChat,
              onOpen: (x) {
                if (x.id != _current?.id) openConversation(x);
              },
              onRename: _rename,
              onDelete: _delete,
              onClose: () => setState(() => _panel = false)),
        ),
      ),
      Expanded(child: chat),
    ]);
  }

  // the messages and the question box share one centred column of at most kRagChatMaxWidth (desktop)
  Widget _chat(BuildContext context) => LayoutBuilder(
      builder: (context, box) => _chatColumn(context, ragGutter(box.maxWidth, min: widget.compact ? AppSpace.sm : AppSpace.md)));

  Widget _chatColumn(BuildContext context, double side) {
    final c = context.colors;
    final hidden = _hiddenBefore.clamp(0, _items.length);
    final visible = hidden == 0 ? _items : _items.sublist(hidden);
    final last = visible.isEmpty ? null : visible.last;
    // no retention notice on the empty chat: "chats are deleted after N days" on a chat just started read as "this new
    // chat gets deleted"; the Chats list (RagSessionsPanel) keeps it at its foot
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.md), children: [
          RagScopeNote(text: _scopeText()),
          const SizedBox(height: AppSpace.md),
          if (_loading) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
          if (hidden > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                key: const ValueKey('rag.earlier'),
                onPressed: () {
                  setState(() => _hiddenBefore = 0);
                  _toEnd();
                },
                icon: Icons.history_rounded,
                size: AppButtonSize.sm,
                label: t('الأسئلة السابقة ($hidden)', 'Earlier questions ($hidden)'),
              ),
            ),
          if (!_loading && visible.isEmpty && _error == null)
            RagStarterPrompts(
                context_: _ctx,
                prompts: _starters,
                onPick: send,
                compact: widget.compact,
                onNewChat: _sessions == true && _current != null ? newChat : null,
                onChats: _sessions == true && _convs.isNotEmpty ? showSessions : null),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Center(
                child: AppButton.ghost(
                    onPressed: _loadingMore ? null : _loadEarlier,
                    busy: _loadingMore,
                    icon: Icons.expand_less_rounded,
                    size: AppButtonSize.sm,
                    label: 'rag_load_earlier'.tr),
              ),
            ),
          for (final a in visible)
            RagAnswerCard(
                answer: a,
                onRate: a.smallTalk ? null : (helpful) => _rate(a, helpful),
                onFollowUp: identical(a, last) && !_sending ? send : null,
                stalled: _stalled.contains(a.id) && !a.done,
                onRetry: _sending ? null : () => _retry(a),
                onNavigate: widget.onNavigate,
                onCitationOpen: (ci) => _learn.signal(a.id, 'chat_citation_open', {'n': ci.n, if (ci.documentId > 0) 'document_id': ci.documentId, 'kind': ci.kind}),
                onDeepLink: (ci) => _learn.signal(a.id, 'chat_deeplink', {'link': ci.deepLink ?? ''}),
                onSupport: a.smallTalk || a.found != false || AppConfig.disableList.contains('profile.help_center') ? null : () => _support(a)),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger)),
        ]),
      ),
      RagComposer(
        controller: _input,
        sending: _sending,
        side: side,
        onSend: () => send(_input.text),
      ),
    ]);
  }

  String _scopeText() {
    final org = widget.contextLabel;
    return switch (_ctx) {
      RagContext.app => t('أجيب من شروط التطبيق وصفحاته وأدلته، مع ذكر المصدر. إن لم تكن الإجابة فيها أخبرك بذلك.',
          'I answer from the app\'s terms, pages and guides, with the source. If the answer is not there, I say so.'),
      RagContext.org => org == null || org.isEmpty
          ? t('أجيب من صفحات التطبيق ومن قواعد مؤسستك ومستنداتها، مع ذكر المصدر.',
              'I answer from the app\'s pages and from your organization\'s rules and documents, with the source.')
          : t('أجيب من صفحات التطبيق ومن قواعد «$org» ومستنداتها، مع ذكر المصدر.',
              'I answer from the app\'s pages and from the rules and documents of "$org", with the source.'),
      RagContext.docs => t('أجيب من مستندات مؤسستك ومقرراتك فقط، مع ذكر المصدر. إن لم تكن الإجابة فيها أخبرك بذلك.',
          'I answer only from your organization\'s and courses\' documents, with the source. If the answer is not there, I say so.'),
    };
  }
}

/// The empty chat: what the assistant can do, as questions to tap; with chat sessions, New chat (when an empty
/// conversation is open) and Chats (when there are earlier ones). The screen's one tinted block (sky: the assistant
/// explains) carries the mark and the editorial greeting; the questions sit under it on one paper card. It enters
/// once per route: the block rises, the questions follow a beat later.
class RagStarterPrompts extends StatelessWidget {
  const RagStarterPrompts({super.key, required this.context_, required this.onPick, this.prompts, this.compact = false, this.onNewChat, this.onChats});
  final RagContext context_;
  final ValueChanged<String> onPick;
  /// The server's questions (built from the library's headings); null or empty = [ragStarterPrompts].
  final List<String>? prompts;
  final bool compact;
  final VoidCallback? onNewChat;
  final VoidCallback? onChats;

  @override
  Widget build(BuildContext context) {
    final list = (prompts == null || prompts!.isEmpty) ? ragStarterPrompts(context_) : prompts!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onNewChat != null || onChats != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (onChats != null) AppButton.ghost(label: 'rag_chats'.tr, icon: Icons.history_rounded, size: AppButtonSize.sm, onPressed: onChats),
            if (onNewChat != null)
              AppButton.secondary(label: 'rag_new_chat'.tr, icon: Icons.add_comment_outlined, size: AppButtonSize.sm, onPressed: onNewChat),
          ]),
        ),
      AppReveal(
        group: 'rag.start',
        index: 0,
        child: AppBlock(
          tone: AppBlockTone.sky,
          hero: !compact,
          padding: compact ? const EdgeInsets.all(AppSpace.md + AppSpace.xxs) : null,
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RagAssistantMark(size: compact ? AppIconSize.xl + AppSpace.xs : AppTouch.min, onBlock: true),
              SizedBox(height: compact ? AppSpace.sm : AppSpace.md),
              Semantics(
                header: true,
                child: Text(t('كيف أساعدك اليوم؟', 'How can I help you today?'),
                    style: (compact ? AppType.pageTitle(context) : AppType.headline(context)).copyWith(color: b.ink)),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(t('اسأل بالعربية أو الإنجليزية — أجيب بلغتك', 'Ask in Arabic or English — I answer in your language'),
                  style: AppType.body(context).copyWith(color: b.muted)),
            ]);
          }),
        ),
      ),
      SizedBox(height: compact ? AppSpace.sm : AppSpace.md),
      AppReveal(group: 'rag.start', index: 1, rise: AppSpace.xs, child: RagPromptList(prompts: list, onPick: onPick)),
    ]);
  }
}

/// The answer as the model writes it (Track E.8): muted, labelled as a draft, a caret at the end that blinks unless
/// the platform asks for reduced motion. It is replaced by the checked answer, so it carries no sources or actions.
class RagPartialAnswer extends StatefulWidget {
  const RagPartialAnswer({super.key, required this.text});
  final String text;

  @override
  State<RagPartialAnswer> createState() => _RagPartialAnswerState();
}

class _RagPartialAnswerState extends State<RagPartialAnswer> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _blink.stop();
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = AppType.body(context).copyWith(height: 1.6);
    return Semantics(
      liveRegion: true,
      label: t('مسودة الإجابة', 'Draft answer'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(t('مسودة — تُراجع مع المصادر', 'Draft — being checked against the sources'), style: AppType.meta(context))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: widget.text),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: FadeTransition(
                opacity: _blink,
                child: Container(
                    width: AppBorder.focus,
                    height: AppIconSize.sm,
                    margin: const EdgeInsetsDirectional.only(start: AppBorder.focus),
                    color: appInk(context, c.primary)),
              ),
            ),
          ]),
          style: base,
        ),
      ]),
    );
  }
}

/// The steps of an answer being prepared, as a rail of four segments under the current step's sentence: done
/// segments are filled, the current one half-filled (they glide as the stage moves on), the rest a warm hairline.
class RagStageTrail extends StatelessWidget {
  const RagStageTrail({super.key, required this.stage});
  final String? stage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = ragStages.indexOf(stage ?? '');
    final labels = [t('فهم', 'Understand'), t('بحث', 'Search'), t('كتابة', 'Write'), t('مراجعة', 'Verify')];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.primary)),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(ragStageText(stage), style: AppType.body(context).copyWith(color: c.textDark))),
      ]),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < ragStages.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xxs),
          Expanded(child: _StageStep(label: labels[i], state: at < 0 ? (i == 0 ? 1 : 0) : (i < at ? 2 : (i == at ? 1 : 0)))),
        ],
      ]),
    ]);
  }
}

class _StageStep extends StatelessWidget {
  const _StageStep({required this.label, required this.state});
  final String label;
  final int state; // 0 to come · 1 now · 2 done

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = state == 0 ? c.textLight : (state == 1 ? c.textDark : c.textMedium);
    return Semantics(
      label: label,
      selected: state == 1,
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: AppSpace.xxs,
            child: ColoredBox(
              color: c.divider,
              child: AppFill(
                value: state == 2 ? 1 : (state == 1 ? 0.5 : 0),
                builder: (context, v) => FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: ColoredBox(color: c.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1, style: AppType.meta(context).copyWith(color: ink, fontWeight: state == 1 ? FontWeight.w600 : FontWeight.w400)),
          ),
        ),
      ]),
    );
  }
}

/// An answer that never came (the assistant's worker is busy or stopped, M16): a calm note and Retry.
class RagStalledNote extends StatelessWidget {
  const RagStalledNote({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.hourglass_disabled_rounded, size: AppIconSize.md, color: c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text('rag_answer_stalled'.tr, style: AppType.body(context).copyWith(height: 1.5))),
      ]),
      if (onRetry != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppButton.tonal(
          key: const ValueKey('rag.retry'),
          label: 'rag_retry'.tr,
          icon: Icons.refresh_rounded,
          size: AppButtonSize.sm,
          onPressed: onRetry,
        ),
      ],
    ]);
  }
}

/// A question and its answer. The question is the asker's note — a paper bubble at the reading end; the answer is
/// set on the page itself like an article (from 480 px with the assistant's mark at its start): the first short
/// paragraph as an editorial lede, the blocks with their `[n]` markers, the passages / tool cards, the sources as
/// paper chips, the page buttons, the follow-ups as rows, then a quiet footer (checked mark, Copy, Helpful?).
class RagAnswerCard extends StatelessWidget {
  const RagAnswerCard(
      {super.key,
      required this.answer,
      this.onRate,
      this.onFollowUp,
      this.onNavigate,
      this.onCitationOpen,
      this.onDeepLink,
      this.onSupport,
      this.onAction,
      this.stalled = false,
      this.onRetry});
  final RagAnswer answer;

  /// Opens an action button (null = [openRagAction], which closes the pop-up through [onNavigate] first).
  final ValueChanged<RagAction>? onAction;

  /// The worker never finished this answer (M16): a calm note with Retry instead of the stage trail.
  final bool stalled;
  final VoidCallback? onRetry;

  /// helpful? (null = no rating offered)
  final void Function(bool helpful)? onRate;

  /// Tapping a suggested question sends it (null = the chips are not shown).
  final ValueChanged<String>? onFollowUp;

  /// Called before a curated source's deep link opens its page (the pop-up closes).
  final VoidCallback? onNavigate;

  /// Track F signals (fire-and-forget, the caller debounces): a source expanded, a deep link followed.
  final ValueChanged<RagCitation>? onCitationOpen;
  final ValueChanged<RagCitation>? onDeepLink;

  /// "Contact support" under the answer (null = not offered: only answers that found nothing offer it).
  final VoidCallback? onSupport;

  /// From this width the answer has the assistant's mark at its start.
  static const double markFrom = 480;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: LayoutBuilder(builder: (context, box) {
        final marked = box.maxWidth >= markFrom;
        final body = RagAnswerArrival(done: answer.done, child: _content(context));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _QuestionNote(text: answer.question, maxWidth: box.maxWidth),
          const SizedBox(height: AppSpace.sm),
          if (marked)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RagAssistantMark(),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: body),
            ])
          else
            body,
        ]);
      }),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    if (!answer.done && stalled) return RagStalledNote(onRetry: onRetry);
    if (!answer.done) {
      if (!answer.provisional) return RagStageTrail(stage: answer.stage);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RagStageTrail(stage: answer.stage),
        const SizedBox(height: AppSpace.md),
        RagPartialAnswer(text: answer.partial!.trim()),
      ]);
    }
    if (answer.state == 'failed') {
      // D-803: asked before the Super Admin switched the assistant off, picked up after: say so, never "ask again"
      if (answer.error == 'feature_disabled') {
        return AppBanner(
            icon: Icons.power_settings_new_rounded,
            color: c.warning,
            text: featureDisabledText(answer.app ? 'rag.app_assistant' : 'rag.assistant'));
      }
      return AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: t('تعذرت الإجابة — أعد السؤال', 'Could not answer — ask again'));
    }
    final nothing = answer.found == false && !answer.smallTalk;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (nothing)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs / 2, end: AppSpace.xs),
            child: Icon(Icons.search_off_rounded, size: AppIconSize.md, color: appInk(context, c.warning)),
          ),
          Expanded(child: RagAnswerBody(text: answer.answer)),
        ])
      else
        RagAnswerBody(text: answer.answer, lede: true),
      // retrieval: the closest passages as cards; tool: the result as a compact card
      if (answer.mode == RagMode.retrieval && answer.chunks.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        RagChunkList(chunks: answer.chunks),
      ],
      if (answer.mode == RagMode.tool && answer.tool != null && !answer.tool!.refused) ...[
        const SizedBox(height: AppSpace.md),
        RagToolCards(tool: answer.tool!),
      ],
      if (answer.citations.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        RagSources(citations: answer.citations, onNavigate: onNavigate, onOpen: onCitationOpen, onDeepLink: onDeepLink),
      ],
      if (ragVisibleActions(answer.actions).isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        RagActionRow(actions: answer.actions, onOpen: (a) => onAction != null ? onAction!(a) : openRagAction(a, beforeOpen: onNavigate)),
      ],
      if (onSupport != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
            label: t('تواصل مع الدعم', 'Contact support'), icon: Icons.support_agent_rounded, size: AppButtonSize.sm, onPressed: onSupport),
      ],
      if (answer.followUps.isNotEmpty && onFollowUp != null) ...[
        const SizedBox(height: AppSpace.sm),
        RagPromptList(prompts: answer.followUps, onPick: onFollowUp!, card: false),
      ],
      const SizedBox(height: AppSpace.xxs),
      _AnswerFooter(answer: answer, onRate: onRate),
    ]);
  }
}

/// The asker's question: a paper note at the reading end, its top end corner tighter (it points at its author).
class _QuestionNote extends StatelessWidget {
  const _QuestionNote({required this.text, required this.maxWidth});
  final String text;
  final double maxWidth;

  /// The widest a question note gets (about 70 characters a line).
  static const double widest = 560;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const big = Radius.circular(AppRadius.card);
    const tight = Radius.circular(AppRadius.chip / 2);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth.isFinite ? (maxWidth * 0.86).clamp(0.0, widest) : widest),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.cardBg,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
            borderRadius: const BorderRadiusDirectional.only(topStart: big, topEnd: tight, bottomStart: big, bottomEnd: big)
                .resolve(Directionality.of(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm - AppSpace.xxs / 2),
            child: Text(text, style: AppType.row(context).copyWith(height: 1.45)),
          ),
        ),
      ),
    );
  }
}

/// Under an answer: "From the sources" (written by the model and checked), Copy, then Helpful? with the thumbs. A
/// Wrap, not a Row: on a 320 px phone with large text they share two lines.
class _AnswerFooter extends StatelessWidget {
  const _AnswerFooter({required this.answer, this.onRate});
  final RagAnswer answer;
  final void Function(bool helpful)? onRate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = AppType.meta(context).copyWith(color: c.textLight);
    return Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xxs, runSpacing: 0, children: [
      if (answer.byModel && !answer.smallTalk)
        Tooltip(
          message: t('إجابة مكتوبة من المصادر وتمت مراجعتها', 'Written from the sources and checked against them'),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_rounded, size: AppIconSize.xs, color: appInk(context, c.success)),
              const SizedBox(width: AppSpace.xxs),
              Flexible(child: Text(t('من المصادر', 'From the sources'), style: quiet)),
            ]),
          ),
        ),
      IconButton(
          tooltip: t('نسخ', 'Copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: answerRuns(answer.answer).where((r) => r.cite == null).map((r) => r.text).join()));
            appToast(t('تم النسخ', 'Copied'));
          },
          icon: Icon(Icons.copy_rounded, size: AppIconSize.sm, color: c.textLight)),
      if (onRate != null) ...[
        Text(t('هل أفادتك؟', 'Helpful?'), style: quiet),
        IconButton(
            tooltip: t('مفيدة', 'Helpful'),
            onPressed: () => onRate!(true),
            icon: Icon(answer.helpful == true ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                size: AppIconSize.md, color: answer.helpful == true ? appInk(context, c.success) : c.textLight)),
        IconButton(
            tooltip: t('غير مفيدة', 'Not helpful'),
            onPressed: () => onRate!(false),
            icon: Icon(answer.helpful == false ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                size: AppIconSize.md, color: answer.helpful == false ? appInk(context, c.danger) : c.textLight)),
      ],
    ]);
  }
}

/// The answer text: paragraphs, bullets and numbered steps, **bold** terms, `[n]` markers in the accent ink. [lede]:
/// a short first paragraph (an answer's opening sentence) is set in the editorial face, the rest in the reading
/// sans at a 1.6 line.
class RagAnswerBody extends StatelessWidget {
  const RagAnswerBody({super.key, required this.text, this.lede = false});
  final String text;
  final bool lede;

  /// The longest first paragraph drawn as a lede (about two lines of the editorial face in the pop-up).
  static const int ledeMaxChars = 160;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary); // the accent as text: readable on the dark canvas too
    final base = AppType.body(context).copyWith(color: c.textDark, height: 1.6);
    final cite = AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600);
    final blocks = answerBlocks(text);
    if (blocks.isEmpty) return Text(text, style: base);
    final first = blocks.first;
    final useLede = lede &&
        first.kind == AnswerBlockKind.paragraph &&
        first.runs.where((r) => r.cite == null).fold<int>(0, (n, r) => n + r.text.length) <= ledeMaxChars;
    final ledeStyle = AppType.section(context).copyWith(fontWeight: FontWeight.w500);
    TextSpan spans(List<AnswerRun> runs) => TextSpan(children: [
          for (final r in runs)
            r.cite != null
                ? TextSpan(text: r.text, style: cite)
                : TextSpan(text: r.text, style: r.bold ? const TextStyle(fontWeight: FontWeight.w600) : null),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(
              top: i == 0
                  ? 0
                  : (i == 1 && useLede)
                      ? AppSpace.sm
                      : (blocks[i].kind == AnswerBlockKind.paragraph ? AppSpace.sm : AppSpace.xxs)),
          child: blocks[i].kind == AnswerBlockKind.paragraph
              ? Text.rich(spans(blocks[i].runs), style: i == 0 && useLede ? ledeStyle : base)
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: AppSpace.lg,
                      child: Text(blocks[i].kind == AnswerBlockKind.bullet ? '•' : '${blocks[i].number}.',
                          style: base.copyWith(color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]))),
                  Expanded(child: Text.rich(spans(blocks[i].runs), style: base)),
                ]),
        ),
    ]);
  }
}
