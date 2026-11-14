// lib/features/org/org_invitation_prompt.dart — "an organization invited you": the notification dialog (contract C7).
//
// An organization never attaches an EXISTING account by itself: an admin who adds an e-mail (one person or an Excel
// sheet) creates a pending invitation, and the person sees it here, right in the app, and accepts or rejects it.
//
//   OrgInvitationPrompt.instance   decides when to fetch and show. While the attention count `org_invitations` is 0 it
//                                  costs NO request. With a count above 0 (or a push tap / the live event
//                                  `org_invitation`) it reads GET /org/public/me/invitations ONCE and shows the newest
//                                  pending invitation that is not snoozed; after one is handled the next one shows.
//   OrgInvitationPromptHost        the tiny widget main.dart's builder holds: it listens to AttentionService and
//                                  LiveEvents and nudges the prompt (it draws nothing of its own).
//   OrgInvitationPromptView        the dialog's content over plain values (layout harness / a11y tests)
//   invitationPromptDue / pickInvitationToShow / InviteSnoozes   the pure rules
//
// Never shown: signed out, on an auth / onboarding / splash route or on an invitation link page, to a parent (parents
// cannot join, D-287), while a live room is open, with organizations switched off or the kill switch `org.invitations`.
// "Later" snoozes that invitation for 24 hours on this device (SharedPreferences, never breaks the app) and stops the
// prompt for this session; closing the dialog any other way counts as Later.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/app_mode.dart';
import '../../core/offline/app_connectivity.dart';
import '../../core/routing/app_routes.dart';
import '../../design/app_kit.dart';
import '../../design/context_switcher.dart' show openJoinedOrganization;
import '../../utils/live_events.dart';
import '../../utils/top_route_observer.dart' show topRouteObserver;
import '../../utils/widget/view_as_state.dart';
import '../admin/admin_common.dart' show asMap, asMapList, t;
import '../auth/auth_provider.dart';
import 'package:flutter_education_app/features/live/live_room_host.dart' show LiveRoomHost;
import 'org_invitations.dart';
import 'org_providers.dart' show OrgSession;
import 'org_v3.dart';

/// How long "Later" keeps one invitation quiet.
const invitationSnooze = Duration(hours: 24);

/// The live event the backend emits to the invitee when an invitation is created (`{invitation_id}`).
const orgInvitationEvent = 'org_invitation';

/// The attention item key (tab `home`) that counts my pending invitations.
const orgInvitationsAttentionKey = AttentionTabs.orgInvitationsItem;

/// Route names the dialog never covers: sign-in, sign-up, onboarding, the splash and the public link pages.
const _quietRoutes = {'/', '/login', '/register', '/onboarding', '/otp', '/forgot-password', '/home', '/guest-search', '/explore'};

bool _quietRoute(String? name) {
  if (name == null || name.isEmpty) return false;
  return _quietRoutes.contains(name) || name.startsWith('/i/') || name.startsWith('/live/') || name.startsWith('/j/');
}

/// The pure gate: true when the prompt may fetch / show now.
bool invitationPromptDue({
  required bool signedIn,
  required String? role,
  required bool orgsEnabled,
  required bool featureOff,
  required bool liveRoomOpen,
  required bool viewAs,
  required bool online,
  required String? routeName,
}) {
  if (!signedIn || viewAs || !online || !orgsEnabled || featureOff || liveRoomOpen) return false;
  if (role == 'parent') return false;
  return !_quietRoute(routeName);
}

enum InviteEventKind { none, count, show }

/// What a live event means for the prompt. Only the `org_invitation` event NAMES an invitation (`show`, one fetch);
/// an attention change (also the one after my own accept / decline) goes through the count check (`count`), which
/// makes no request while the count is 0; an `org_invitation` event with no id counts too.
({InviteEventKind kind, int? id}) invitationEventAction(String type, String? relatedType, Map<String, dynamic> data) {
  if (type == LiveEvents.attentionChanged) {
    return (kind: relatedType == 'org_invitation' ? InviteEventKind.count : InviteEventKind.none, id: null);
  }
  final id = int.tryParse('${data['invitation_id'] ?? ''}');
  return id == null ? (kind: InviteEventKind.count, id: null) : (kind: InviteEventKind.show, id: id);
}

/// "Later" memory: invitation id → when it was snoozed (epoch ms).
class InviteSnoozes {
  InviteSnoozes([Map<int, int>? m]) : _m = {...?m};
  final Map<int, int> _m;

  bool isSnoozed(int id, DateTime now) {
    final at = _m[id];
    return at != null && now.difference(DateTime.fromMillisecondsSinceEpoch(at)) < invitationSnooze;
  }

  void snooze(int id, DateTime now) => _m[id] = now.millisecondsSinceEpoch;

  /// Drops the entries whose day has passed.
  void prune(DateTime now) => _m.removeWhere((_, at) => now.difference(DateTime.fromMillisecondsSinceEpoch(at)) >= invitationSnooze);

  /// `id:ms` pairs, the form kept in SharedPreferences.
  List<String> encode() => [for (final e in _m.entries) '${e.key}:${e.value}'];

  static InviteSnoozes decode(List<String>? raw) {
    final m = <int, int>{};
    for (final s in raw ?? const <String>[]) {
      final p = s.split(':');
      final id = p.length == 2 ? int.tryParse(p[0]) : null, at = p.length == 2 ? int.tryParse(p[1]) : null;
      if (id != null && at != null) m[id] = at;
    }
    return InviteSnoozes(m);
  }
}

/// The invitation to show: [onlyId] (a push tap) wins even when snoozed; else the newest pending one that is not
/// snoozed or in [skip] (already handled in this run). Expired rows are never offered.
MyInvitation? pickInvitationToShow(List<MyInvitation> all, InviteSnoozes snoozes, DateTime now, {int? onlyId, Set<int> skip = const {}}) {
  final live = [
    for (final i in all)
      if (!skip.contains(i.id) && (i.expiresAt == null || i.expiresAt!.isAfter(now))) i
  ];
  if (onlyId != null) {
    for (final i in live) {
      if (i.id == onlyId) return i;
    }
    return null;
  }
  live.sort((a, b) {
    final c = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  for (final i in live) {
    if (!snoozes.isSnoozed(i.id, now)) return i;
  }
  return null;
}

/// What the person did in the dialog.
enum InviteChoice { accepted, opened, rejected, later, gone }

// ═════════════════════════════════════════════════════════════════════════════
//  The dialog's content (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class OrgInvitationPromptView extends StatelessWidget {
  const OrgInvitationPromptView({
    super.key,
    required this.invitation,
    this.busy,
    this.error,
    this.accepted = false,
    this.gone = false,
    this.onAccept,
    this.onReject,
    this.onLater,
    this.onOpen,
    this.onClose,
  });

  final MyInvitation invitation;

  /// 'accept' | 'reject' while that call runs (its button spins, the others wait).
  final String? busy;
  final String? error;

  /// Accepted: the dialog now offers "Open the organization".
  final bool accepted;

  /// The invitation can't be answered any more (expired, cancelled …): only Close is left.
  final bool gone;
  final VoidCallback? onAccept, onReject, onLater, onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = invitation;
    final idle = busy == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        AppAvatar(name: i.orgName, url: i.logoUrl),
        AppSpace.gapSm,
        Expanded(child: Text(i.orgName, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
      ]),
      AppSpace.gapSm,
      if (accepted)
        AppBanner(icon: Icons.check_circle_rounded, color: c.success, text: t('أصبحت عضواً في «${i.orgName}».', 'You are now a member of "${i.orgName}".'))
      else ...[
        Text(
          t('تمت دعوتك للانضمام إلى هذه المؤسسة بصفة ${i.roleLabel}.', 'You are invited to join this organization as ${i.roleLabel}.'),
          style: AppType.body(context),
        ),
        if (i.invitedByName.isNotEmpty) ...[
          AppSpace.gapXs,
          Text(t('الدعوة من ${i.invitedByName}', 'Invited by ${i.invitedByName}'), style: AppType.meta(context)),
        ],
        if (i.message.isNotEmpty) ...[
          AppSpace.gapSm,
          Container(
            key: const ValueKey('org.invite_prompt.message'),
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.primaryWash, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Text(i.message, style: AppType.body(context)),
          ),
        ],
        AppSpace.gapXs,
        Text(inviteExpiryText(i.expiresAt), style: AppType.meta(context)),
      ],
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      AppSpace.gapMd,
      if (accepted)
        AppButtonRow(
          primary: AppButton.primary(key: const ValueKey('org.invite_prompt.open'), label: t('فتح المؤسسة', 'Open the organization'), onPressed: onOpen),
          secondary: [AppButton.ghost(key: const ValueKey('org.invite_prompt.done'), label: t('تم', 'Done'), onPressed: onClose)],
        )
      else if (gone)
        AppButtonRow(primary: AppButton.primary(key: const ValueKey('org.invite_prompt.close'), label: t('إغلاق', 'Close'), onPressed: onClose))
      else
        AppButtonRow(
          primary: AppButton.primary(
              key: const ValueKey('org.invite_prompt.accept'),
              label: t('قبول', 'Accept'),
              icon: Icons.check_rounded,
              busy: busy == 'accept',
              onPressed: idle ? onAccept : null),
          secondary: [
            AppButton.ghost(key: const ValueKey('org.invite_prompt.later'), label: t('لاحقاً', 'Later'), onPressed: idle ? onLater : null),
            AppButton.danger(key: const ValueKey('org.invite_prompt.reject'), label: t('رفض', 'Reject'), busy: busy == 'reject', onPressed: idle ? onReject : null),
          ],
        ),
    ]);
  }
}

/// The dialog body: runs the calls and pops the dialog with an [InviteChoice].
class OrgInvitationPromptBody extends StatefulWidget {
  const OrgInvitationPromptBody({super.key, required this.invitation, this.api, this.afterAccepted, this.confirmReject, this.openOrg});

  final MyInvitation invitation;
  final OrgInvitationsApi? api;

  /// Runs after an accept succeeded (reload the memberships). Default: [AppModeController] + [OrgSession].
  final Future<void> Function(BuildContext context)? afterAccepted;

  /// Asks before a rejection (tests pass `(_) async => true`). Default: [appConfirm].
  final Future<bool> Function(BuildContext context)? confirmReject;

  /// "Open the organization". Default: [openJoinedOrganization].
  final Future<void> Function(BuildContext context, MyInvitation i)? openOrg;

  @override
  State<OrgInvitationPromptBody> createState() => _OrgInvitationPromptBodyState();
}

class _OrgInvitationPromptBodyState extends State<OrgInvitationPromptBody> {
  late final OrgInvitationsApi _api = widget.api ?? OrgInvitationsApi();
  String? _busy, _error;
  bool _accepted = false, _gone = false;

  static const _goneCodes = {'invite_not_pending', 'invite_expired', 'invite_not_found', 'org_unavailable', 'membership_ended'};

  Future<void> _accept() async {
    setState(() {
      _busy = 'accept';
      _error = null;
    });
    final r = await _api.acceptMine(widget.invitation.id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = null;
        _error = orgErrorText(r.error!);
        _gone = _goneCodes.contains(r.code);
      });
      return;
    }
    setState(() {
      _busy = null;
      _accepted = true;
    });
    try {
      await (widget.afterAccepted ?? _reloadMemberships)(context);
    } catch (_) {/* the memberships reload on the next pass anyway */}
  }

  Future<void> _reject() async {
    final ok = await (widget.confirmReject ?? _confirmReject)(context);
    if (!ok || !mounted) return;
    setState(() {
      _busy = 'reject';
      _error = null;
    });
    final r = await _api.declineMine(widget.invitation.id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = null;
        _error = orgErrorText(r.error!);
        _gone = _goneCodes.contains(r.code);
      });
      return;
    }
    showAppNotice(t('رُفضت الدعوة', 'Invitation declined'));
    Navigator.of(context).pop(InviteChoice.rejected);
  }

  Future<bool> _confirmReject(BuildContext context) => appConfirm(context,
      message: t('رفض الدعوة إلى «${widget.invitation.orgName}»؟ يمكن للمؤسسة دعوتك مرة أخرى بعد 7 أيام.',
          'Reject the invitation to "${widget.invitation.orgName}"? The organization can invite you again after 7 days.'),
      danger: true,
      confirmLabel: t('رفض الدعوة', 'Reject'));

  /// I am a member now: the memberships (the switcher, the mode) and the dashboard's organizations reload - the same
  /// as after answering a `/i/<token>` link.
  static Future<void> _reloadMemberships(BuildContext context) async {
    unawaited(AppModeController.instance.refresh());
    try {
      unawaited(context.read<OrgSession>().load());
    } catch (_) {/* no OrgSession in scope */}
  }

  Future<void> _open() async {
    final i = widget.invitation;
    final nav = Navigator.of(context);
    nav.pop(InviteChoice.opened);
    final ctx = navigatorContext();
    if (ctx == null) return;
    if (widget.openOrg != null) return widget.openOrg!(ctx, i);
    await AppModeController.instance.ready();
    if (!ctx.mounted) return;
    await openJoinedOrganization(ctx, i.orgId, staff: i.memberRole.isNotEmpty ? i.memberRole != 'student' : i.role != 'student');
  }

  @override
  Widget build(BuildContext context) => OrgInvitationPromptView(
        invitation: widget.invitation,
        busy: _busy,
        error: _error,
        accepted: _accepted,
        gone: _gone,
        onAccept: _accept,
        onReject: _reject,
        onLater: () => Navigator.of(context).pop(InviteChoice.later),
        onOpen: _open,
        onClose: () => Navigator.of(context).pop(_accepted ? InviteChoice.accepted : InviteChoice.gone),
      );
}

/// Shows the dialog for [i]; resolves to what the person chose (closing it any other way is [InviteChoice.later]).
Future<InviteChoice> showOrgInvitationDialog(
  BuildContext context,
  MyInvitation i, {
  OrgInvitationsApi? api,
  Future<void> Function(BuildContext context)? afterAccepted,
  Future<bool> Function(BuildContext context)? confirmReject,
  Future<void> Function(BuildContext context, MyInvitation i)? openOrg,
}) async {
  final r = await showAppDialog<InviteChoice>(
    context,
    title: t('دعوة للانضمام إلى مؤسسة', 'Invitation to join an organization'),
    icon: Icons.mark_email_unread_rounded,
    body: OrgInvitationPromptBody(invitation: i, api: api, afterAccepted: afterAccepted, confirmReject: confirmReject, openOrg: openOrg),
  );
  return r ?? InviteChoice.later;
}

// ═════════════════════════════════════════════════════════════════════════════
//  The trigger
// ═════════════════════════════════════════════════════════════════════════════

/// The context of the root Navigator (set by the host; null before it is mounted).
BuildContext? navigatorContext() => OrgInvitationPrompt._activeKey?.currentContext;

class OrgInvitationPrompt {
  OrgInvitationPrompt._();

  static final OrgInvitationPrompt instance = OrgInvitationPrompt._();

  /// A test builds its own, with fakes for the outside world.
  @visibleForTesting
  OrgInvitationPrompt.test({
    this.api,
    this.clock = DateTime.now,
    this.countProbe,
    this.gate,
    this.dialog,
    this.store,
    this.userId,
    this.onGone,
  });

  static GlobalKey<NavigatorState>? _activeKey;
  MyAuthProvider? _auth;

  // injectable parts
  OrgInvitationsApi? api;
  DateTime Function() clock = DateTime.now;
  int Function()? countProbe;
  bool Function()? gate;
  Future<InviteChoice> Function(BuildContext context, MyInvitation i)? dialog;
  InviteSnoozeStore? store;
  int? Function()? userId;

  /// What happens when a tap names an invitation that is no longer pending (tests replace it).
  Future<void> Function()? onGone;

  /// One queued tap (a push tap while the dialog was busy or the gate shut): handled when the gate opens.
  ({int? id, int? uid})? _queued;
  Timer? _drain;
  int _drainTries = 0;

  bool _busy = false;
  bool _laterThisSession = false;
  int _lastCount = 0;
  DateTime? _lastFetch;
  final _handled = <int>{};
  int fetchCount = 0; // requests made (tests)

  /// The host hands in the Navigator and the auth state.
  void attach(GlobalKey<NavigatorState> navigatorKey, MyAuthProvider? auth) {
    _activeKey = navigatorKey;
    _auth = auth;
  }

  int? get _uid => userId != null ? userId!() : _auth?.currentUser?.id;

  /// Signed out or another person signed in: nothing queued for the last one may survive.
  void clearQueued() {
    _queued = null;
    _drain?.cancel();
    _drain = null;
    _drainTries = 0;
  }

  /// A new person signs in: forget this run's memory.
  void reset() {
    _laterThisSession = false;
    _lastCount = 0;
    _lastFetch = null;
    _handled.clear();
  }

  int _attentionCount() {
    final probe = countProbe;
    if (probe != null) return probe();
    var n = 0;
    for (final x in AttentionService.instance.items(AttentionTabs.home)) {
      if (x.key == orgInvitationsAttentionKey) n += x.count;
    }
    return n;
  }

  bool _allowed() {
    final g = gate;
    if (g != null) return g();
    final auth = _auth;
    return invitationPromptDue(
      signedIn: auth?.isAuthenticated ?? false,
      role: auth?.currentUser?.role,
      orgsEnabled: AppConfig.orgsEnabled,
      featureOff: AppConfig.disableList.contains(invitationsFeatureKey),
      liveRoomOpen: LiveRoomHost.isOpen,
      viewAs: ViewAsState.active,
      online: AppConnectivity.instance.isOnline,
      routeName: topRouteObserver.currentRoute?.settings.name,
    );
  }

  /// The attention count changed (or a timer fired): shows the dialog when there is something waiting. With a count
  /// of 0 this returns without a request.
  Future<void> onAttention() async {
    final n = _attentionCount();
    if (n <= 0) {
      _lastCount = 0;
      return;
    }
    if (_laterThisSession || !_allowed()) return;
    // the same count, already read a short while ago and nothing to show then: no second read
    final recent = _lastFetch != null && clock().difference(_lastFetch!) < const Duration(minutes: 10);
    if (n == _lastCount && recent) return;
    await _run(null, count: n);
  }

  /// A push tap or the live event for [invitationId] (null = just the newest): shows it even when snoozed. When the
  /// dialog is busy or the gate is shut the tap is queued (one) and handled when it opens; when the invitation is
  /// not pending any more the person is told and My organizations opens.
  Future<void> showFor(int? invitationId) async {
    if (_busy || !_allowed()) {
      _queue(invitationId);
      return;
    }
    await _run(invitationId, force: true);
  }

  void _queue(int? id) {
    _queued = (id: id, uid: _uid);
    _drainTries = 0;
    _drain ??= Timer.periodic(const Duration(seconds: 2), (_) => unawaited(drainQueued()));
  }

  /// Handles the queued tap when nothing blocks it any more (also called by the host).
  Future<void> drainQueued() async {
    final q = _queued;
    if (q == null) {
      _drain?.cancel();
      _drain = null;
      return;
    }
    if (q.uid != null && q.uid != _uid) {
      clearQueued();
      return;
    }
    if (_busy || !_allowed()) {
      if (++_drainTries > 30) clearQueued(); // a minute of waiting is enough
      return;
    }
    clearQueued();
    await _run(q.id, force: true);
  }

  Future<void> _goneNotice() async {
    final custom = onGone;
    if (custom != null) return custom();
    showAppNotice(t('لم تعد هذه الدعوة متاحة', 'This invitation is no longer available'), error: true);
    final nav = _activeKey?.currentState;
    if (nav != null) await nav.pushNamed(AppRoutes.location(AppRoutes.orgMemberships.id));
  }

  Future<void> _run(int? onlyId, {bool force = false, int? count}) async {
    if (_busy) return;
    _busy = true;
    final uid = _uid;
    var gone = false;
    try {
      final r = await (api ?? OrgInvitationsApi()).mine();
      fetchCount++;
      if (uid != _uid) return; // another person signed in meanwhile: this answer is not theirs
      _lastFetch = clock();
      if (count != null) _lastCount = count;
      if (!r.ok) return;
      final items = [for (final x in asMapList(asMap(r.data)['items'])) MyInvitation.fromJson(x)];
      final snoozes = await _loadSnoozes(uid);
      var asked = onlyId;
      if (asked != null && !items.any((x) => x.id == asked && (x.expiresAt == null || x.expiresAt!.isAfter(clock())))) {
        gone = true;
        return;
      }
      while (true) {
        final i = pickInvitationToShow(items, snoozes, clock(), onlyId: asked, skip: _handled);
        if (i == null) break;
        final ctx = navigatorContext();
        if (uid != _uid || ctx == null || !ctx.mounted || !_allowed()) break;
        _handled.add(i.id);
        final choice = await (dialog ?? showOrgInvitationDialog)(ctx, i);
        if (choice == InviteChoice.later) {
          snoozes.snooze(i.id, clock());
          await _saveSnoozes(snoozes, uid);
          if (!force) _laterThisSession = true;
          break;
        }
        if (choice == InviteChoice.opened) break;
        asked = null; // the next one in line
        if (_laterThisSession || uid != _uid) break;
      }
    } catch (e) {
      // a prompt must never break the app
      if (kDebugMode) debugPrint('[org invitation prompt] $e');
    } finally {
      _busy = false;
      if (gone) {
        await _goneNotice();
      } else if (_queued != null) {
        unawaited(drainQueued());
      }
    }
  }

  static String _userKey(int? uid) => 'org_invite_later_${uid ?? 0}';

  Future<InviteSnoozes> _loadSnoozes(int? uid) async {
    try {
      final s = store ?? const _PrefsSnoozeStore();
      final m = InviteSnoozes.decode(await s.read(_userKey(uid)));
      m.prune(clock());
      return m;
    } catch (_) {
      return InviteSnoozes();
    }
  }

  Future<void> _saveSnoozes(InviteSnoozes s, int? uid) async {
    try {
      await (store ?? const _PrefsSnoozeStore()).write(_userKey(uid), s.encode());
    } catch (_) {/* not remembered: it asks again, nothing breaks */}
  }
}

/// Where the snoozes live (SharedPreferences; a map in tests).
abstract class InviteSnoozeStore {
  Future<List<String>?> read(String key);
  Future<void> write(String key, List<String> value);
}

class _PrefsSnoozeStore implements InviteSnoozeStore {
  const _PrefsSnoozeStore();

  @override
  Future<List<String>?> read(String key) async => (await SharedPreferences.getInstance()).getStringList(key);

  @override
  Future<void> write(String key, List<String> value) async => (await SharedPreferences.getInstance()).setStringList(key, value);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The host (main.dart's builder)
// ═════════════════════════════════════════════════════════════════════════════

/// Wraps the Navigator; draws nothing of its own. While someone is signed in it listens to the attention feed and to
/// the live event `org_invitation` and nudges [OrgInvitationPrompt]. Signed out it listens to nothing (so the
/// attention polling stays off on the sign-in screens).
class OrgInvitationPromptHost extends StatefulWidget {
  const OrgInvitationPromptHost({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<OrgInvitationPromptHost> createState() => _OrgInvitationPromptHostState();
}

class _OrgInvitationPromptHostState extends State<OrgInvitationPromptHost> {
  MyAuthProvider? _auth;
  bool _listening = false;
  StreamSubscription<LiveEvent>? _live;
  Timer? _settle, _retry;
  int _retries = 0;

  static const settle = Duration(milliseconds: 1500);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MyAuthProvider? auth;
    try {
      auth = Provider.of<MyAuthProvider>(context, listen: false);
    } catch (_) {/* no auth provider above (tests) */}
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onAuth);
      _auth = auth?..addListener(_onAuth);
      OrgInvitationPrompt.instance.attach(widget.navigatorKey, auth);
    }
    _onAuth();
  }

  int? _uid;

  /// Parents never see the prompt (they cannot join): for them nothing is listened to at all. Everyone else already
  /// has a home with an AttentionBadge mounted under every pushed page (the shell stays in the Navigator), so this
  /// listener adds no polling the homes would not run anyway.
  bool get _wantsFeed => (_auth?.isAuthenticated ?? false) && _auth?.currentUser?.role != 'parent';

  void _onAuth() {
    final signedIn = _auth?.isAuthenticated ?? false;
    final uid = _auth?.currentUser?.id;
    if (_listening && (!signedIn || uid != _uid)) {
      _stop();
    }
    if (signedIn && !_listening && _wantsFeed) {
      _listening = true;
      _uid = uid;
      OrgInvitationPrompt.instance.reset();
      AttentionService.instance.addListener(_onAttention);
      _live = LiveEvents.instance.listen({orgInvitationEvent, LiveEvents.attentionChanged}, _onEvent);
    }
  }

  void _stop() {
    _listening = false;
    _uid = null;
    AttentionService.instance.removeListener(_onAttention);
    _live?.cancel();
    _live = null;
    _settle?.cancel();
    _retry?.cancel();
    OrgInvitationPrompt.instance
      ..clearQueued()
      ..reset();
  }

  void _onAttention() {
    _settle?.cancel();
    _settle = Timer(settle, _check);
  }

  Future<void> _check() async {
    if (!mounted) return;
    await OrgInvitationPrompt.instance.onAttention();
    // waiting on a route that is not allowed yet (sign-in just finished, a live room): look again a few times
    final p = OrgInvitationPrompt.instance;
    if (p._attentionCount() > 0 && !p._laterThisSession && p._lastFetch == null && _retries < 12) {
      _retries++;
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 5), _check);
    } else {
      _retries = 0;
    }
  }

  void _onEvent(LiveEvent e) {
    final act = invitationEventAction(e.type, e.relatedType, e.data);
    if (act.kind == InviteEventKind.none) return;
    if (act.kind == InviteEventKind.count) {
      _onAttention();
      return;
    }
    final id = act.id;
    _settle?.cancel();
    _settle = Timer(settle, () {
      if (mounted) unawaited(OrgInvitationPrompt.instance.showFor(id));
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    if (_listening) _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
