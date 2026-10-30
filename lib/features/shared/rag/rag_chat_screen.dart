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
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'rag_chat.dart';
import 'rag_chat_sessions.dart';
import 'rag_library.dart';
import 'rag_learning.dart';
import 'rag_library_screen.dart';
import 'package:flutter_education_app/design/app_icons.dart';

export 'rag_chat_sessions.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key, this.orgId, this.courseId, this.app = false, this.title, this.conversationId});
  final int? orgId;
  final int? courseId;
  final bool app;
  final String? title;

  /// The conversation to open (the pop-up's current one when it expands); null = the latest.
  final int? conversationId;

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  final _chat = GlobalKey<RagChatViewState>();
  bool _manager = false; // library managers get the Library action (from the documents list: manager: true)
  bool _sessions = false; // the server has chat sessions: New chat + Chats actions

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.assistant'),
      appBar: ScreenAppBar(title: widget.title ?? (widget.app ? t('مساعد التطبيق', 'App assistant') : t('مساعد المستندات', 'Documents assistant')),
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

  @override
  void initState() {
    super.initState();
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
      final a = r.ok ? RagAnswer.fromJson(r.map) : null;
      if (a != null) _items[i] = a;
      if (a == null || !a.done) _stalled.add(id);
    });
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
    await showAppSheet<void>(context, (ctx) => RagSessionsPanel(
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
    if (_current?.id != conversation?.id) return; // the person moved to another chat meanwhile
    setState(() {
      _items.add(pending);
      _touchCurrent();
    });
    _toEnd();
    final done = await _api.waitFor(pending.id, onUpdate: (a) {
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
      // no answer in time (or the polling failed): the card turns into a calm error with Retry (M16)
      if (!done.ok || !RagAnswer.fromJson(done.map).done) _stalled.add(pending.id);
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
      builder: (context, box) => _chatColumn(context, ragGutter(box.maxWidth, min: widget.compact ? 12.0 : 16.0)));

  Widget _chatColumn(BuildContext context, double side) {
    final c = context.colors;
    final hidden = _hiddenBefore.clamp(0, _items.length);
    final visible = hidden == 0 ? _items : _items.sublist(hidden);
    final last = visible.isEmpty ? null : visible.last;
    final retention = _sessions == true && !_loading && _items.isEmpty ? retentionText(_retentionDays, AppConfig.lang) : '';
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: EdgeInsets.fromLTRB(side, 8, side, 16), children: [
          AppBanner(icon: Icons.menu_book_rounded, color: appInk(context, c.primary), text: _scopeText()),
          const SizedBox(height: 10),
          if (_loading) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
          if (hidden > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('rag.earlier'),
                onPressed: () {
                  setState(() => _hiddenBefore = 0);
                  _toEnd();
                },
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(t('الأسئلة السابقة ($hidden)', 'Earlier questions ($hidden)')),
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
          if (retention.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppBanner(icon: Icons.auto_delete_outlined, color: c.textMedium, text: retention),
          ],
          if (_hasMore)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                  onPressed: _loadingMore ? null : _loadEarlier,
                  icon: _loadingMore
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_less_rounded, size: 18),
                  label: Text('rag_load_earlier'.tr)),
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
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger)),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 4, side, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: EnterSubmits(
                    onSubmit: () => send(_input.text),
                    child: AppField(controller: _input, label: t('اسألني أي شيء…', 'Ask me anything…'), maxLines: 3))),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: t('إرسال', 'Send'),
              onPressed: _sending ? null : () => send(_input.text),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
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
/// conversation is open) and Chats (when there are earlier ones).
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
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onNewChat != null || onChats != null)
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          if (onNewChat != null) OutlinedButton.icon(onPressed: onNewChat, icon: const Icon(Icons.add_comment_outlined, size: 18), label: Text('rag_new_chat'.tr)),
          if (onChats != null) TextButton.icon(onPressed: onChats, icon: const Icon(Icons.history_rounded, size: 18), label: Text('rag_chats'.tr)),
        ]),
      Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 12 : 24),
        child: Column(children: [
          Container(
            width: 56, height: 56, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome_rounded, color: appInk(context, c.primary), size: 28),
          ),
          const SizedBox(height: 10),
          Text(t('كيف أساعدك اليوم؟', 'How can I help you today?'), textAlign: TextAlign.center, style: appText(16, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: 4),
          Text(t('اسأل بالعربية أو الإنجليزية — أجيب بلغتك', 'Ask in Arabic or English — I answer in your language'),
              textAlign: TextAlign.center, style: appText(12.5, c: c.textMedium)),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final p in (prompts == null || prompts!.isEmpty) ? ragStarterPrompts(context_) : prompts!)
          AppChoiceChip(label: p, selected: false, onTap: () => onPick(p), icon: Icons.chat_bubble_outline_rounded),
      ]),
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
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: c.textMedium);
    return Semantics(
      liveRegion: true,
      label: t('مسودة الإجابة', 'Draft answer'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: 16, color: c.textLight),
          const SizedBox(width: 4),
          Expanded(child: Text(t('مسودة — تُراجع مع المصادر', 'Draft — being checked against the sources'), style: appText(11.5, c: c.textLight))),
        ]),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: widget.text),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: FadeTransition(
                opacity: _blink,
                child: Container(
                    width: 2,
                    height: 16,
                    margin: const EdgeInsetsDirectional.only(start: 2),
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

/// The steps of an answer being prepared: done · current · to come.
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
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
        const SizedBox(width: 8),
        Expanded(child: Text(ragStageText(stage), style: appText(13, c: c.textMedium))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (var i = 0; i < ragStages.length; i++)
          _StageDot(label: labels[i], state: at < 0 ? (i == 0 ? 1 : 0) : (i < at ? 2 : (i == at ? 1 : 0))),
      ]),
    ]);
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.label, required this.state});
  final String label;
  final int state; // 0 to come · 1 now · 2 done

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = state == 0 ? c.textLight : appInk(context, state == 1 ? c.primary : c.success);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(state == 2 ? Icons.check_circle_rounded : (state == 1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded), size: 14, color: col),
      const SizedBox(width: 3),
      Text(label, style: appText(11.5, w: state == 1 ? FontWeight.w700 : FontWeight.w500, c: col)),
    ]);
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
        Icon(Icons.hourglass_disabled_rounded, size: 18, color: c.textMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'rag_answer_stalled'.tr,
            style: appText(13.5, c: c.textMedium, h: 1.45),
          ),
        ),
      ]),
      if (onRetry != null)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('rag.retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('rag_retry'.tr),
          ),
        ),
    ]);
  }
}

/// A question and its answer: the answer's blocks with their `[n]` markers, the follow-ups, then the sources it quotes.
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
      this.stalled = false,
      this.onRetry});
  final RagAnswer answer;

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Text(answer.question, style: theme.bodyMedium),
          ),
        ),
        const SizedBox(height: 6),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: !answer.done && stalled
              ? RagStalledNote(onRetry: onRetry)
              : !answer.done
              ? (answer.provisional
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      RagStageTrail(stage: answer.stage),
                      const SizedBox(height: 10),
                      RagPartialAnswer(text: answer.partial!.trim()),
                    ])
                  : RagStageTrail(stage: answer.stage))
              : answer.state == 'failed'
                  ? AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: t('تعذرت الإجابة — أعد السؤال', 'Could not answer — ask again'))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (answer.found == false && !answer.smallTalk)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.search_off_rounded, size: 18, color: c.warning),
                          const SizedBox(width: 6),
                          Expanded(child: RagAnswerBody(text: answer.answer)),
                        ])
                      else
                        RagAnswerBody(text: answer.answer),
                      if (answer.citations.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(t('المصادر', 'Sources'), style: theme.labelMedium?.copyWith(color: c.textMedium)),
                        const SizedBox(height: 4),
                        for (final ci in answer.citations)
                          _Source(
                              citation: ci,
                              onNavigate: onNavigate,
                              onOpen: onCitationOpen == null ? null : () => onCitationOpen!(ci),
                              onDeepLink: onDeepLink == null ? null : () => onDeepLink!(ci)),
                      ],
                      if (onSupport != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                              onPressed: onSupport,
                              icon: const Icon(Icons.support_agent_rounded, size: 18),
                              label: Text(t('تواصل مع الدعم', 'Contact support'))),
                        ),
                      if (answer.followUps.isNotEmpty && onFollowUp != null) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final f in answer.followUps)
                            AppChoiceChip(label: f, selected: false, onTap: () => onFollowUp!(f), icon: DirIcons.arrowOutward),
                        ]),
                      ],
                      // a Wrap, not a Row: on a 320 px phone with large text the badge, Copy and the rating share two lines
                      Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                        if (answer.byModel && !answer.smallTalk)
                          Tooltip(
                            message: t('إجابة مكتوبة من المصادر وتمت مراجعتها', 'Written from the sources and checked against them'),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.verified_rounded, size: 14, color: c.success),
                              const SizedBox(width: 3),
                              Text(t('من المصادر', 'From the sources'), style: appText(11, c: c.textLight)),
                            ]),
                          ),
                        IconButton(
                            tooltip: t('نسخ', 'Copy'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: answerRuns(answer.answer).where((r) => r.cite == null).map((r) => r.text).join()));
                              appToast(t('تم النسخ', 'Copied'));
                            },
                            icon: Icon(Icons.copy_rounded, size: 16, color: c.textLight)),
                        if (onRate != null) ...[
                          Text(t('هل أفادتك؟', 'Helpful?'), style: theme.bodySmall?.copyWith(color: c.textLight)),
                          IconButton(
                              tooltip: t('مفيدة', 'Helpful'), onPressed: () => onRate!(true),
                              icon: Icon(answer.helpful == true ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, size: 18,
                                  color: answer.helpful == true ? c.success : c.textLight)),
                          IconButton(
                              tooltip: t('غير مفيدة', 'Not helpful'), onPressed: () => onRate!(false),
                              icon: Icon(answer.helpful == false ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined, size: 18,
                                  color: answer.helpful == false ? c.danger : c.textLight)),
                        ],
                      ]),
                    ]),
        ),
      ]),
    );
  }
}

/// The answer text: paragraphs, bullets and numbered steps, **bold** terms, `[n]` markers in the accent colour.
class RagAnswerBody extends StatelessWidget {
  const RagAnswerBody({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary); // the accent as text: readable on the dark card too
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    final blocks = answerBlocks(text);
    if (blocks.isEmpty) return Text(text, style: base);
    TextSpan spans(List<AnswerRun> runs) => TextSpan(children: [
          for (final r in runs)
            r.cite != null
                ? TextSpan(text: r.text, style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12))
                : TextSpan(text: r.text, style: r.bold ? const TextStyle(fontWeight: FontWeight.w800) : null),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : (blocks[i].kind == AnswerBlockKind.paragraph ? 8 : 3)),
          child: blocks[i].kind == AnswerBlockKind.paragraph
              ? Text.rich(spans(blocks[i].runs), style: base)
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 22,
                      child: Text(blocks[i].kind == AnswerBlockKind.bullet ? '•' : '${blocks[i].number}.',
                          style: base?.copyWith(color: ink, fontWeight: FontWeight.w800))),
                  Expanded(child: Text.rich(spans(blocks[i].runs), style: base)),
                ]),
        ),
    ]);
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.citation, this.onNavigate, this.onOpen, this.onDeepLink});
  final RagCitation citation;
  final VoidCallback? onNavigate;
  final VoidCallback? onOpen, onDeepLink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final module = citation.isQa ? ragDeepLinkModule(citation.deepLink) : null;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: 34, bottom: 8),
        dense: true,
        onExpansionChanged: (open) {
          if (open) onOpen?.call();
        },
        leading: Semantics(
          label: t('المصدر ${citation.n}', 'Source ${citation.n}'),
          excludeSemantics: true,
          child: CircleAvatar(radius: 12, backgroundColor: c.primary.withValues(alpha: 0.12),
              child: citation.isQa
                  ? Icon(Icons.question_answer_outlined, size: 13, color: appInk(context, c.primary))
                  : Text('${citation.n}', style: TextStyle(fontSize: 11, color: appInk(context, c.primary), fontWeight: FontWeight.w700))),
        ),
        title: Text(citation.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.bodySmall),
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: Text('«${citation.quote}»', style: theme.bodySmall?.copyWith(color: c.textMedium))),
          if (module != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                  onPressed: () {
                    onDeepLink?.call();
                    onNavigate?.call();
                    AppNavigator.openModule(module);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('rag_open_link'.tr)),
            ),
        ],
      ),
    );
  }
}
