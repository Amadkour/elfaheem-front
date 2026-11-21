// lib/features/org/org_must_ack.dart
//
// Institutions S4, the recipient's side (contract docs/institutions/CONTRACT_S4.md, back D-975 – D-978):
//   OrgMustAckHost        in MaterialApp.builder, just inside LiveRoomLayer (main.dart). It reads GET /me/must-ack
//                         after sign-in, on app resume (at most every 30 s), on the `org_must_ack` live event and
//                         when a live exam / live room closes — no timer. While a live exam (LiveFocus) or a live
//                         room (LiveRoomHost) is open it asks nothing and shows nothing (D-977). The card covers
//                         the app (focus and semantics of the pages below are excluded) until "I have read this";
//                         the acknowledge answer's `next` is shown at once (the queue, one at a time).
//                         A second source (student lifecycle phase 4, D-1400): GET /api/v1/org/me/asks — an open ask
//                         with presentation `fullscreen` covers the app until answered (drawn AFTER the must-ack
//                         messages: a message waiting wins), one with `popup` shows as a card with "Later" (put off for
//                         this session). Read on the same triggers plus the `student_lifecycle` live event; switch
//                         org.students.asks. The form is MyAskOverlay (students/my_ask_page.dart);
//                         test/org/must_ack_asks_test.dart.
//   MustAckCardView       the full-screen card, plain values (test/org/institutions_s4_test.dart)
//   OrgMyMessagesPage     "Organization messages": GET /me/org-messages, reloads on `org_message`; a row opens
//                         MemberMessageView in a sheet (GET …/{mid} marks it read) with the reply: the org chat with
//                         the sender, or the complaint / request thread
// Kill switches: org.messages (everything), org.messages.must_ack (the card).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live_focus.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/live/live_room_host.dart' show LiveRoomHost;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import 'org_messages_models.dart';
import 'org_v3.dart' show OrgCall;
import 'students/my_ask_page.dart' show MyAsk, MyAskOverlay, MyAskSource, MyAsksState, RemoteMyAskSource, myAsksEnabled, myAsksShouldAsk;

// ═════════════════════════════════════════════════════════════════════════════
//  The host
// ═════════════════════════════════════════════════════════════════════════════

/// Where the host reads and acknowledges (tests give a fake).
abstract class MustAckSource {
  Future<MustAckState> fetch();
  Future<OrgCall> acknowledge(int id);
}

class RemoteMustAckSource implements MustAckSource {
  const RemoteMustAckSource();

  @override
  Future<MustAckState> fetch() => MsgApi.mustAck();

  @override
  Future<OrgCall> acknowledge(int id) => MsgApi.acknowledge(id);
}

class OrgMustAckHost extends StatefulWidget {
  const OrgMustAckHost({super.key, required this.child, this.source = const RemoteMustAckSource(), this.asks, this.signedIn});

  final Widget child;
  final MustAckSource source;

  /// The asks source; null = the server's when [source] is the server's (a test that fakes only the messages gets
  /// no asks).
  final MyAskSource? asks;

  /// Tests: whether someone is signed in (else MyAuthProvider decides).
  final bool Function()? signedIn;

  /// How long a resume waits after the last read before it asks again.
  static const resumeGap = Duration(seconds: 30);

  @override
  State<OrgMustAckHost> createState() => _OrgMustAckHostState();
}

class _OrgMustAckHostState extends State<OrgMustAckHost> with WidgetsBindingObserver {
  MustAckState _state = MustAckState.none;
  MyAsksState _asks = MyAsksState.none;
  final _later = <int>{};                                 // popups put off this session
  Future<void>? _runningAsks;
  bool _asksAgain = false;                                // a forced read came while one was in flight
  final _gone = <int>{};                                  // answered / closed here: hidden until a read that started after
  bool _busy = false, _wasSignedIn = false, _askLater = false, _hidingAssistant = false;
  String? _error;
  DateTime? _lastAsk;
  Future<void>? _running;
  StreamSubscription<LiveEvent>? _live;
  MyAuthProvider? _auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _live = LiveEvents.instance.listen({LiveEvents.orgMustAck, LiveEvents.studentLifecycle},
        (e) => _ask(force: true, ack: e.type == LiveEvents.orgMustAck, asks: e.type != LiveEvents.orgMustAck));
    LiveFocus.examOpen.addListener(_onFocus);
    LiveRoomHost.listenable.addListener(_onFocus);
    AppConfig.disableListVersion.addListener(_onSwitch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.signedIn == null) {
        try {
          _auth = context.read<MyAuthProvider>()..addListener(_onAuth);
        } catch (_) {/* no auth provider above (a test host): signed out */}
      }
      _onAuth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live?.cancel();
    LiveFocus.examOpen.removeListener(_onFocus);
    LiveRoomHost.listenable.removeListener(_onFocus);
    AppConfig.disableListVersion.removeListener(_onSwitch);
    _auth?.removeListener(_onAuth);
    if (_hidingAssistant) AppAssistant.release();
    super.dispose();
  }

  bool get _signedIn => widget.signedIn?.call() ?? (_auth?.isAuthenticated ?? false);

  MyAskSource? get _askSource => widget.asks ?? (widget.source is RemoteMustAckSource ? const RemoteMyAskSource() : null);

  bool get _blocked => !mustAckMayShow(examOpen: LiveFocus.isExamOpen, roomOpen: LiveRoomHost.isOpen);

  void _onAuth() {
    final s = _signedIn;
    if (s && !_wasSignedIn) {
      _wasSignedIn = true;
      _ask(force: true);
    } else if (!s && _wasSignedIn) {
      _wasSignedIn = false;
      _later.clear();
      _gone.clear();
      _set(MustAckState.none);
      _setAsks(MyAsksState.none);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _ask();
  }

  /// A live exam / room opened or closed (the flag flips in a dispose: never set state there).
  void _onFocus() => scheduleMicrotask(() {
        if (!mounted) return;
        if (!_blocked && _askLater) {
          _ask(force: true);
        } else {
          setState(() {});
        }
      });

  void _onSwitch() => scheduleMicrotask(() {
        if (mounted && !orgMustAckEnabled()) _set(MustAckState.none);
        if (mounted && !myAsksEnabled()) _setAsks(MyAsksState.none);
      });

  void _set(MustAckState s) {
    if (!mounted) return;
    setState(() {
      _state = s;
      _error = null;
    });
  }

  void _setAsks(MyAsksState s) {
    if (!mounted) return;
    setState(() => _asks = s);
  }

  /// [ack]: read the must-ack messages, [asks]: read my open asks (both by default).
  void _ask({bool force = false, bool ack = true, bool asks = true}) {
    final ackOk = ack && mustAckShouldAsk(signedIn: _signedIn, viewAs: ViewAsState.active);
    final asksOk = asks && _askSource != null && myAsksShouldAsk(signedIn: _signedIn, viewAs: ViewAsState.active);
    if (ack && !ackOk && _state.item != null) _set(MustAckState.none);
    if (asks && !asksOk && _asks.items.isNotEmpty) _setAsks(MyAsksState.none);
    if (!ackOk && !asksOk) return;
    if (_blocked) {
      _askLater = true;                                   // read it again when the exam / room closes
      return;
    }
    final now = DateTime.now();
    if (!force && _lastAsk != null && now.difference(_lastAsk!) < OrgMustAckHost.resumeGap) return;
    _askLater = false;
    _lastAsk = now;
    if (ackOk && _running == null) {
      _running = widget.source.fetch().then(_set).whenComplete(() => _running = null);
    }
    if (asksOk) _readAsks(again: force);
  }

  /// GET /me/asks once at a time. A forced read while one is in flight ([again]) is queued: the in-flight answer is
  /// dropped (it may predate an answer or a close) and one more read runs after it. [_gone] ids known before a read
  /// started are cleared when it lands: from then on the server's answer decides (a returned ask shows again).
  void _readAsks({bool again = false}) {
    final src = _askSource;
    if (src == null) return;
    if (_runningAsks != null) {
      if (again) _asksAgain = true;
      return;
    }
    final known = {..._gone};
    _runningAsks = src.fetch().then((s) {
      if (_asksAgain || !mounted) return;
      _gone.removeAll(known);
      _setAsks(s);
    }).whenComplete(() {
      _runningAsks = null;
      if (_asksAgain && mounted) {
        _asksAgain = false;
        _readAsks();
      }
    });
  }

  /// The ask [a] is done or closed here: hide it now, then read the asks again.
  void _dropAsk(MyAsk a) {
    if (mounted) setState(() => _gone.add(a.id));
    _ask(force: true, ack: false);
  }

  void _askAnswered(MyAsk a) {
    _dropAsk(a);
    showAppNotice(t('أُرسل ردّك', 'Your answer was sent'));
  }

  /// A failed answer: read the asks again (an ask that closed meanwhile must never keep the app covered). A closed
  /// one shows "closed" with Close ([_dropAsk]) until the read lands and takes it away.
  void _askFailed(MyAsk a) => _ask(force: true, ack: false);

  void _putOff(MyAsk a) => setState(() => _later.add(a.id));

  Future<void> _acknowledge() async {
    final m = _state.item;
    if (m == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.source.acknowledge(m.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _set(MustAckState.fromJson(asMap(r.map['next'])));
      return;
    }
    final c = r.code;
    if (c == 'message_expired' || c == 'message_not_found' || c == 'not_must_ack') {
      _ask(force: true);                                  // gone on the server: show what is next instead
      return;
    }
    setState(() => _error = msgErrorText(r.error!));
  }

  @override
  Widget build(BuildContext context) {
    final m = _state.item;
    final free = !_blocked && _signedIn;
    final showAck = m != null && free && orgMustAckEnabled();
    final asksOn = free && !showAck && _askSource != null && myAsksEnabled();
    final full = asksOn ? _asks.nextFullscreen(_gone) : null;
    final pop = asksOn && full == null ? _asks.nextPopup({..._later, ..._gone}) : null;
    final show = showAck || full != null || pop != null;
    if (show != _hidingAssistant) {
      _hidingAssistant = show;
      show ? AppAssistant.hide() : AppAssistant.release();     // the floating bubble never sits on the card
    }
    return Stack(fit: StackFit.expand, children: [
      ExcludeFocus(excluding: show, child: ExcludeSemantics(excluding: show, child: widget.child)),
      if (full != null || pop != null)
        Positioned.fill(
          child: MyAskOverlay(
            key: ValueKey('my_ask.${(full ?? pop)!.id}'),
            ask: (full ?? pop)!,
            source: _askSource!,
            fullscreen: full != null,
            onAnswered: _askAnswered,
            onFailed: _askFailed,
            onClose: () => _dropAsk((full ?? pop)!),
            onLater: pop == null ? null : () => _putOff(pop),
          ),
        ),
      if (showAck)
        Positioned.fill(
          child: MustAckCardView(
            key: ValueKey('must_ack.${m.id}'),
            message: m,
            queued: _state.queued,
            busy: _busy,
            error: _error,
            onAcknowledge: _acknowledge,
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The card
// ═════════════════════════════════════════════════════════════════════════════

/// The full-screen, non-dismissible card: sender, reason, text, "I have read this". Plain values.
class MustAckCardView extends StatelessWidget {
  const MustAckCardView({super.key, required this.message, required this.onAcknowledge, this.queued = 0, this.busy = false, this.error});

  final OrgMessage message;
  final int queued;
  final bool busy;
  final String? error;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    return Material(
      color: c.background,
      child: SafeArea(
        child: FocusScope(
          autofocus: true,
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: t('رسالة تحتاج إلى إقرار', 'A message you must acknowledge'),
            child: LayoutBuilder(builder: (context, box) {
              final gutter = AppWidth.gutter(box.maxWidth);
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: AppSpace.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          Container(
                            width: AppTouch.min,
                            height: AppTouch.min,
                            decoration: BoxDecoration(color: appToneTint(context, AppTone.warning), shape: BoxShape.circle),
                            child: Icon(Icons.mark_email_unread_rounded, color: appToneInk(context, AppTone.warning), size: AppIconSize.lg),
                          ),
                          AppSpace.gapSm,
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('إقرار إلزامي', 'Must acknowledge'), style: AppType.overline(context).copyWith(color: appToneInk(context, AppTone.warning))),
                              if ((m.orgName ?? '').isNotEmpty)
                                Text(m.orgName!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                            ]),
                          ),
                        ]),
                        AppSpace.gapMd,
                        Semantics(
                          header: true,
                          child: Text(m.title, style: AppType.headline(context)),
                        ),
                        AppSpace.gapXs,
                        Text(
                          '${t('من', 'From')}: ${m.fromLine.isEmpty ? t('إدارة المؤسسة', 'The organization') : m.fromLine}',
                          style: AppType.meta(context),
                        ),
                        if (m.reason != null) ...[
                          AppSpace.gapMd,
                          Container(
                            padding: const EdgeInsets.all(AppSpace.sm),
                            decoration: BoxDecoration(color: c.primaryWash, borderRadius: AppRadius.cardAll),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('السبب', 'Reason'), style: AppType.label(context).copyWith(color: c.textMedium)),
                              const SizedBox(height: AppSpace.xxs),
                              Text(m.reason!, style: AppType.bodyStrong(context)),
                            ]),
                          ),
                        ],
                        AppSpace.gapMd,
                        Text(m.body, style: AppType.body(context).copyWith(height: 1.6)),
                        if (m.expiresAt != null) ...[
                          AppSpace.gapMd,
                          Text('${t('متاحة حتى', 'Open until')} ${AppTime.dateTime(m.expiresAt!.toUtc())}', style: AppType.meta(context)),
                        ],
                        if (error != null) ...[
                          AppSpace.gapSm,
                          Text(error!, style: AppType.body(context).copyWith(color: c.danger)),
                        ],
                        AppSpace.gapLg,
                        AppButton.primary(
                          key: const ValueKey('must_ack.ok'),
                          label: t('قرأتُ هذه الرسالة', 'I have read this'),
                          icon: Icons.check_rounded,
                          busy: busy,
                          expand: true,
                          onPressed: busy ? null : onAcknowledge,
                        ),
                        if (queued > 0) ...[
                          AppSpace.gapSm,
                          Text(mustAckQueuedText(queued), textAlign: TextAlign.center, style: AppType.meta(context)),
                        ],
                      ]),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The member's messages
// ═════════════════════════════════════════════════════════════════════════════

/// One row of the member's list. Plain values.
class MemberMessageCard extends StatelessWidget {
  const MemberMessageCard({super.key, required this.message, required this.onTap});

  final OrgMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    final waiting = m.needsAck && m.ackedAt == null;
    return AppCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(m.unread ? Icons.mark_email_unread_rounded : Icons.drafts_rounded, color: m.unread ? c.primary : c.textLight, size: AppIconSize.lg),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: m.unread ? AppType.bodyStrong(context) : AppType.row(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (m.fromLine.isNotEmpty) Text(m.fromLine, style: AppType.meta(context)),
              if (m.createdAt != null) Text(AppTime.dateTime(m.createdAt!.toUtc()), style: AppType.meta(context)),
              if (waiting) AppStatusBadge(label: t('بانتظار إقرارك', 'Waiting for you'), tone: AppTone.warning, dense: true),
              if (m.needsAck && m.ackedAt != null) AppStatusBadge(label: t('أقررتَ بها', 'Acknowledged'), tone: AppTone.success, dense: true),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// The open message with its reply. Plain values.
class MemberMessageView extends StatelessWidget {
  const MemberMessageView({super.key, required this.message, this.onReplyChat, this.onReplyItem, this.onAcknowledge, this.busy = false});

  final OrgMessage message;
  final VoidCallback? onReplyChat, onReplyItem, onAcknowledge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    final r = m.reply;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(m.fromLine, style: AppType.meta(context)),
      if (m.createdAt != null) Text(AppTime.dateTime(m.createdAt!.toUtc()), style: AppType.meta(context)),
      if (m.reason != null) ...[
        AppSpace.gapSm,
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.primaryWash, borderRadius: AppRadius.cardAll),
          child: Text('${t('السبب', 'Reason')}: ${m.reason}', style: AppType.body(context)),
        ),
      ],
      AppSpace.gapMd,
      SelectableText(m.body, style: AppType.body(context).copyWith(height: 1.6)),
      AppSpace.gapLg,
      if (m.needsAck && m.ackedAt == null && onAcknowledge != null) ...[
        AppButton.primary(label: t('قرأتُ هذه الرسالة', 'I have read this'), icon: Icons.check_rounded, busy: busy, expand: true, onPressed: onAcknowledge),
        AppSpace.gapSm,
      ],
      if (m.ackedAt != null)
        Text('${t('أقررتَ بها', 'Acknowledged')} ${AppTime.dateTime(m.ackedAt!.toUtc())}', style: AppType.meta(context).copyWith(color: c.success)),
      if (r != null && r.isChat && onReplyChat != null)
        AppButton.secondary(label: t('الرد في الرسائل', 'Reply in Messages'), icon: Icons.chat_bubble_outline_rounded, expand: true, onPressed: onReplyChat),
      if (r != null && r.isItem)
        onReplyItem != null
            ? AppButton.secondary(
                label: r.workItemId != null ? t('الرد في الطلب', 'Reply in the request') : t('الرد في الشكوى', 'Reply in the complaint'),
                icon: Icons.forum_outlined,
                expand: true,
                onPressed: onReplyItem)
            : Text(t('للرد اكتب في الشكوى أو الطلب نفسه.', 'To reply, write in the complaint or request itself.'), style: AppType.meta(context)),
    ]);
  }
}

/// "Organization messages" (one organization, or all of mine when [orgId] is null); [openId] opens that message once
/// the list loaded (a push / notification tap). [onOpenItem] opens a complaint / request thread (the member space).
class OrgMyMessagesPage extends StatefulWidget {
  const OrgMyMessagesPage({super.key, this.orgId, this.openId, this.onOpenItem});

  final int? orgId, openId;
  final void Function(BuildContext context, MsgReply reply)? onOpenItem;

  @override
  State<OrgMyMessagesPage> createState() => _OrgMyMessagesPageState();
}

class _OrgMyMessagesPageState extends State<OrgMyMessagesPage> {
  List<OrgMessage>? _items;
  int _unread = 0;
  bool _failed = false, _opened = false;
  StreamSubscription<LiveEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = LiveEvents.instance.listen({LiveEvents.orgMessage, LiveEvents.orgMustAck}, (_) => _load());
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await MsgApi.myMessages(orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      _failed = !r.ok;
      if (r.ok) {
        _items = [for (final j in asMapList(r.map['items'])) OrgMessage.fromJson(j)];
        _unread = (r.map['unread'] as num?)?.toInt() ?? 0;
      }
    });
    final id = widget.openId;
    if (r.ok && id != null && !_opened) {
      _opened = true;
      _open(id);
    }
  }

  Future<void> _open(int id) async {
    final open = widget.onOpenItem;
    await showAppSheet<void>(context, (ctx) => _MemberMessageSheet(id: id, onOpenItem: open == null ? null : (r) => open(context, r)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    Widget body;
    if (items == null) {
      body = _failed
          ? AppErrorState(onRetry: _load)
          : const AppListSkeleton(items: 4);
    } else if (items.isEmpty) {
      body = AppEmpty(icon: Icons.mark_email_read_rounded, title: t('لا رسائل', 'No messages'),
          message: t('رسائل مؤسستك إليك تظهر هنا.', 'Messages from your organization show here.'));
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => AppSpace.gapSm,
          itemBuilder: (_, i) => i == 0
              ? Text(
                  _unread > 0
                      ? countText(_unread, ar1: 'رسالة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '{n} رسائل غير مقروءة', arMany: '{n} رسالة غير مقروءة',
                          en1: '1 unread message', en: '{n} unread messages')
                      : t('كل الرسائل مقروءة', 'Every message is read'),
                  style: AppType.meta(context))
              : MemberMessageCard(message: items[i - 1], onTap: () => _open(items[i - 1].id)),
        ),
      );
    }
    return BasePage(
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('رسائل المؤسسة', 'Organization messages')),
      child: body,
    );
  }
}

class _MemberMessageSheet extends StatefulWidget {
  const _MemberMessageSheet({required this.id, this.onOpenItem});
  final int id;

  /// Runs on the list page's context (the sheet is closed first).
  final void Function(MsgReply reply)? onOpenItem;

  @override
  State<_MemberMessageSheet> createState() => _MemberMessageSheetState();
}

class _MemberMessageSheetState extends State<_MemberMessageSheet> {
  OrgMessage? _m;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await MsgApi.myMessage(widget.id);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _m = OrgMessage.fromJson(r.map);
      } else {
        _error = msgErrorText(r.error!);
      }
    });
  }

  Future<void> _ack() async {
    setState(() => _busy = true);
    final r = await MsgApi.acknowledge(widget.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(msgErrorText(r.error!), error: true);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final reply = m?.reply;
    return AppSheetContent(
      title: m?.title ?? t('رسالة', 'Message'),
      icon: Icons.mail_rounded,
      children: [
        if (m == null && _error == null) const AppListSkeleton(items: 2),
        if (_error != null) Text(_error!, style: AppType.body(context).copyWith(color: context.colors.danger)),
        if (m != null)
          MemberMessageView(
            message: m,
            busy: _busy,
            onAcknowledge: _ack,
            onReplyChat: reply == null || !reply.isChat
                ? null
                : () {
                    final nav = AppShellNav.navigatorFor(context);
                    Navigator.pop(context);
                    nav.pushNamed('/chat', arguments: {'peer_id': reply.peerId, 'org_id': reply.orgId ?? m.orgId});
                  },
            onReplyItem: reply == null || !reply.isItem || widget.onOpenItem == null
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onOpenItem!(reply);
                  },
          ),
      ],
    );
  }
}
