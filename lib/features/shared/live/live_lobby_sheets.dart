// lib/features/shared/live/live_lobby_sheets.dart
//
// The UI of live-room share links and the admission lobby (spec: docs/backend/live-rooms-spec.md §6). The pure
// models and the API are in live_room.dart. Every presentational widget here takes plain values + callbacks so the
// layout harness can pump it (test/ui/live_lobby_layout_test.dart):
//
//   LiveLobbyController     ChangeNotifier the host's room / lobby sheet drive: polls GET …/lobby every 15 s (4 s
//                           while the LobbySheet is open, nothing in the background), refreshes at once on the
//                           silent push (LiveLobbyEvents, then one follow-up 4 s later) and on resume, plays a short
//                           system sound + haptic on a new request and keeps it as [latestNew] for the banner.
//   LobbySheet / LobbyBody  the waiting list (avatar / initials, Admit · Reject · Admit all) and the two switches
//                           "Everyone needs my approval" / "Guests join automatically". showLobbySheet(context, ref).
//   ShareLinkSheet / ShareLinkBody   the room's share link for meetings (can-publish, max guests, PIN, copy / share /
//                           QR / settings / revoke) — mirrors the session guest-link sheet. showShareLinkSheet(…).
//   WaitingForHostPage / WaitingForHostScreen   the joiner's "Waiting for the host…" (animated, cancel) with the
//                           rejected / expired end states; the page polls the request until a decision.
//   LobbyBanner             the in-room strip "X wants to join" with Admit / Reject inline.
//
// Strings: t(ar, en) from admin_common.dart (no translation.json edits). Switches: AppSwitchTile only.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart' show ApiException;
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart' show t;
import '../guest/guest_live_api.dart' show guestPinValid;
import 'live_room.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Keeps one room's lobby fresh. The room creates it for the host, starts it, hands `waitingCount` to the control
/// bar and `latestNew` to the banner; the lobby sheet shares the same instance when opened from the room.
///
/// The poll schedule — every interval is a constructor parameter so a test can run it on a fake clock:
///   · lobby sheet open   → every [pollWhileOpen] (4 s), and at once when it opens ([sheetOpened]);
///   · sheet closed       → every [pollIdle] (15 s);
///   · the silent push `live_join_request` ([LiveLobbyEvents]) → at once, then one follow-up after
///     [pushFollowUp] (4 s) — a second request often arrives right behind the first;
///   · back in the foreground → at once; in the background nothing is polled (WidgetsBindingObserver).
/// Every refresh, whatever triggered it, schedules the next poll from the moment it finishes.
class LiveLobbyController extends ChangeNotifier with WidgetsBindingObserver {
  LiveLobbyController(
    this.ref, {
    LiveRoomApi? api,
    this.sound = true,
    this.pollWhileOpen = kLobbyPollEvery,
    this.pollIdle = kLobbyPollIdle,
    this.pushFollowUp = kLobbyPollEvery,
  }) : api = api ?? LiveRoomApi(ref);

  final LiveRoomRef ref;
  final LiveRoomApi api;

  /// Play the system alert + a haptic on a new request.
  final bool sound;

  /// Poll interval while a [LobbySheet] shows this controller's list.
  final Duration pollWhileOpen;

  /// Poll interval while no sheet is open (the room alone).
  final Duration pollIdle;

  /// The one quick poll after a push-triggered refresh.
  final Duration pushFollowUp;

  List<LobbyRequest> waiting = const [];
  List<LobbyRequest> admittedRecent = const [];
  LiveAdmission admission = LiveAdmission.open;
  LiveGuestAdmission guestAdmission = LiveGuestAdmission.approve;
  bool loading = false;
  bool loaded = false;
  String? error;

  /// Request ids a decision is in flight for (their buttons show busy).
  final Set<String> busy = {};

  /// The newest request the host has not acted on or dismissed — the room's banner.
  LobbyRequest? latestNew;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _fetching = false;
  int _sheetsOpen = 0;
  bool _background = false;
  bool _followUpDue = false;

  int get waitingCount => waiting.length;

  /// True while a [LobbySheet] shows this controller's list (the [pollWhileOpen] cadence).
  bool get sheetOpen => _sheetsOpen > 0;

  /// True while the app is in the background: nothing is polled until it resumes.
  bool get inBackground => _background;

  /// True while a poll is scheduled.
  bool get polling => _timer != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Refreshes once, starts the poll schedule, the push listener and the lifecycle observer; idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    LiveLobbyEvents.latest.addListener(_onPush);
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _background = _isBackground(binding.lifecycleState);
    if (_background) return; // the resume refreshes and starts the schedule
    unawaited(refresh()); // schedules the next poll when it completes
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    _followUpDue = false;
    LiveLobbyEvents.latest.removeListener(_onPush);
    WidgetsBinding.instance.removeObserver(this);
  }

  /// A [LobbySheet] started showing the list: refresh now and poll every [pollWhileOpen] until [sheetClosed].
  void sheetOpened() {
    _sheetsOpen++;
    if (_sheetsOpen != 1 || !_started || _background) return;
    if (_fetching) {
      _scheduleNext(); // the running refresh is fresh enough; only the cadence changes
    } else {
      unawaited(refresh());
    }
  }

  /// The sheet left the screen: back to the [pollIdle] cadence.
  void sheetClosed() {
    if (_sheetsOpen == 0) return;
    _sheetsOpen--;
    if (_sheetsOpen == 0 && !_fetching) _scheduleNext();
  }

  void _onPush() {
    final data = LiveLobbyEvents.latest.value;
    if (data == null) return;
    final r = LiveLobbyEvents.refOf(data);
    if (r != null && r != ref) return;
    _followUpDue = true; // the refresh after this one comes after pushFollowUp, not the cadence
    if (_background) return; // picked up by the resume refresh
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = _isBackground(state);
    if (bg == _background || !_started) return;
    _background = bg;
    if (bg) {
      _timer?.cancel();
      _timer = null;
    } else {
      unawaited(refresh());
    }
  }

  /// `inactive` is still on screen (a system dialog, the notification shade); only these stop the polling.
  static bool _isBackground(AppLifecycleState? s) =>
      s == AppLifecycleState.paused || s == AppLifecycleState.hidden || s == AppLifecycleState.detached;

  /// Books the next poll from now: the follow-up after a push, else the open / idle cadence.
  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    if (!_started || _disposed || _background) return;
    final Duration after;
    if (_followUpDue) {
      _followUpDue = false;
      after = pushFollowUp;
    } else {
      after = sheetOpen ? pollWhileOpen : pollIdle;
    }
    _timer = Timer(after, () {
      _timer = null;
      unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_disposed || _fetching) return;
    _fetching = true;
    if (!loaded) {
      loading = true;
      notifyListeners();
    }
    try {
      final s = await api.lobby();
      if (_disposed) return;
      final fresh = newLobbyRequests(waiting, s.waiting);
      waiting = s.waiting;
      admittedRecent = s.admittedRecent;
      admission = s.admission;
      guestAdmission = s.guestAdmission;
      error = null;
      loaded = true;
      if (fresh.isNotEmpty && loaded) {
        latestNew = fresh.last;
        _alert();
      } else if (latestNew != null && !waiting.any((w) => w.id == latestNew!.id)) {
        latestNew = null; // decided elsewhere (another device, admit-all)
      }
    } catch (e) {
      if (_disposed) return;
      error = liveRoomErrorText(e);
    } finally {
      _fetching = false;
      if (!_disposed) {
        loading = false;
        notifyListeners();
        _scheduleNext();
      }
    }
  }

  void _alert() {
    if (!sound) return;
    try {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.mediumImpact());
    } catch (_) {}
  }

  void dismissBanner() {
    if (latestNew == null) return;
    latestNew = null;
    notifyListeners();
  }

  Future<bool> _decide(String id, Future<void> Function() fn) async {
    if (busy.contains(id)) return false;
    busy.add(id);
    notifyListeners();
    try {
      await fn();
      waiting = [for (final w in waiting) if (w.id != id) w];
      if (latestNew?.id == id) latestNew = null;
      error = null;
      return true;
    } catch (e) {
      error = liveRoomErrorText(e);
      appToast(error!, error: true);
      return false;
    } finally {
      busy.remove(id);
      if (!_disposed) notifyListeners();
      unawaited(refresh());
    }
  }

  Future<bool> admit(String id) => _decide(id, () => api.admit(id));

  Future<bool> reject(String id) => _decide(id, () => api.reject(id));

  Future<bool> admitAll() async {
    if (busy.contains('*')) return false;
    busy.add('*');
    notifyListeners();
    try {
      await api.admitAll();
      waiting = const [];
      latestNew = null;
      error = null;
      return true;
    } catch (e) {
      error = liveRoomErrorText(e);
      appToast(error!, error: true);
      return false;
    } finally {
      busy.remove('*');
      if (!_disposed) notifyListeners();
      unawaited(refresh());
    }
  }

  Future<void> setAdmission(LiveAdmission a) async {
    final prev = admission;
    admission = a;
    notifyListeners();
    try {
      final p = await api.setPolicy(admission: a);
      admission = p.admission;
      guestAdmission = p.guestAdmission;
    } catch (e) {
      admission = prev;
      appToast(liveRoomErrorText(e), error: true);
    }
    if (!_disposed) notifyListeners();
    unawaited(refresh());
  }

  Future<void> setGuestAdmission(LiveGuestAdmission a) async {
    final prev = guestAdmission;
    guestAdmission = a;
    notifyListeners();
    try {
      final p = await api.setPolicy(guestAdmission: a);
      admission = p.admission;
      guestAdmission = p.guestAdmission;
    } catch (e) {
      guestAdmission = prev;
      appToast(liveRoomErrorText(e), error: true);
    }
    if (!_disposed) notifyListeners();
    unawaited(refresh());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lobby sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the lobby of [ref]. Pass the room's [controller] to share its state; otherwise one is created for the sheet.
Future<void> showLobbySheet(BuildContext context, LiveRoomRef ref, {LiveLobbyController? controller}) =>
    showAppSheet<void>(context, (_) => LobbySheet(ref: ref, controller: controller));

class LobbySheet extends StatefulWidget {
  const LobbySheet({super.key, required this.ref, this.controller});

  final LiveRoomRef ref;
  final LiveLobbyController? controller;

  @override
  State<LobbySheet> createState() => _LobbySheetState();
}

class _LobbySheetState extends State<LobbySheet> {
  late final LiveLobbyController _c = widget.controller ?? LiveLobbyController(widget.ref);
  late final bool _own = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _c.start(); // the room's controller already runs; this is a no-op then
    _c.sheetOpened(); // refresh now, then the 4 s cadence while the list is on screen
    // A banner for the request being shown in the list is redundant.
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.dismissBanner());
  }

  @override
  void dispose() {
    _c.sheetClosed();
    if (_own) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (_, _) => LobbyBody(
          loading: _c.loading && !_c.loaded,
          error: _c.error,
          waiting: _c.waiting,
          busyIds: _c.busy,
          everyoneNeedsApproval: _c.admission == LiveAdmission.approve,
          guestsJoinAutomatically: _c.guestAdmission == LiveGuestAdmission.auto,
          onAdmit: (id) => _c.admit(id),
          onReject: (id) => _c.reject(id),
          onAdmitAll: _c.admitAll,
          onRefresh: _c.refresh,
          onEveryoneNeedsApproval: (v) => _c.setAdmission(v ? LiveAdmission.approve : LiveAdmission.open),
          onGuestsJoinAutomatically: (v) => _c.setGuestAdmission(v ? LiveGuestAdmission.auto : LiveGuestAdmission.approve),
        ),
      );
}

/// The lobby's layout (plain values).
class LobbyBody extends StatelessWidget {
  const LobbyBody({
    super.key,
    required this.loading,
    required this.error,
    required this.waiting,
    required this.everyoneNeedsApproval,
    required this.guestsJoinAutomatically,
    required this.onAdmit,
    required this.onReject,
    required this.onAdmitAll,
    required this.onRefresh,
    required this.onEveryoneNeedsApproval,
    required this.onGuestsJoinAutomatically,
    this.busyIds = const {},
  });

  final bool loading;
  final String? error;
  final List<LobbyRequest> waiting;

  /// Ids with a decision in flight ('*' = admit all).
  final Set<String> busyIds;
  final bool everyoneNeedsApproval;
  final bool guestsJoinAutomatically;
  final ValueChanged<String> onAdmit;
  final ValueChanged<String> onReject;
  final VoidCallback onAdmitAll;
  final VoidCallback onRefresh;
  final ValueChanged<bool>? onEveryoneNeedsApproval;
  final ValueChanged<bool>? onGuestsJoinAutomatically;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allBusy = busyIds.contains('*');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(
        t('غرفة الانتظار', 'Lobby'),
        trailing: IconButton(
          key: const ValueKey('lobby.refresh'),
          tooltip: t('تحديث', 'Refresh'),
          onPressed: loading ? null : onRefresh,
          icon: Icon(Icons.refresh_rounded, color: c.primary),
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Waiting ──────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: AppSectionTitle(
                  waiting.isEmpty ? t('بانتظار الدخول', 'Waiting to join') : '${t('بانتظار الدخول', 'Waiting to join')} (${waiting.length})',
                ),
              ),
              if (waiting.length > 1)
                AppPill(
                  key: const ValueKey('lobby.admit_all'),
                  icon: Icons.done_all_rounded,
                  label: t('قبول الكل', 'Admit all'),
                  color: c.success,
                  onTap: allBusy || loading ? null : onAdmitAll,
                ),
            ]),
            const SizedBox(height: 6),
            if (loading)
              const SizedBox(height: 180, child: AppListSkeleton(items: 3, withAvatar: true, padding: EdgeInsets.zero))
            else if (error != null && waiting.isEmpty)
              AppBanner(
                key: const ValueKey('lobby.error'),
                icon: Icons.wifi_off_rounded,
                text: error!,
                color: c.danger,
                action: IconButton(onPressed: onRefresh, icon: Icon(Icons.refresh_rounded, color: c.danger)),
              )
            else if (waiting.isEmpty)
              AppEmpty(
                key: const ValueKey('lobby.empty'),
                icon: Icons.meeting_room_outlined,
                title: t('لا أحد ينتظر', 'Nobody is waiting'),
                message: t('من يطلب الانضمام يظهر هنا فوراً.', 'Anyone who asks to join shows up here right away.'),
              )
            else
              for (var i = 0; i < waiting.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                LobbyRequestRow(
                  request: waiting[i],
                  busy: allBusy || busyIds.contains(waiting[i].id),
                  onAdmit: () => onAdmit(waiting[i].id),
                  onReject: () => onReject(waiting[i].id),
                ),
              ],
            if (error != null && waiting.isNotEmpty) ...[
              const SizedBox(height: 8),
              AppBanner(icon: Icons.wifi_off_rounded, text: error!, color: c.textMedium),
            ],

            // ── Rules ────────────────────────────────────────────────────
            const SizedBox(height: 18),
            AppSectionTitle(t('من يدخل مباشرة؟', 'Who gets in without asking?')),
            AppSwitchTile(
              key: const ValueKey('lobby.everyone_approval'),
              title: t('الجميع يحتاج موافقتي', 'Everyone needs my approval'),
              subtitle: t('حتى الطلاب والمدعوون ينتظرون حتى تقبلهم.', 'Even students and invitees wait until you admit them.'),
              icon: Icons.how_to_reg_rounded,
              value: everyoneNeedsApproval,
              onChanged: onEveryoneNeedsApproval,
            ),
            AppSwitchTile(
              key: const ValueKey('lobby.guests_auto'),
              title: t('الزوار يدخلون تلقائياً', 'Guests join automatically'),
              subtitle: t('من يأتي عبر رابط المشاركة يدخل دون انتظار.', 'Visitors from the share link come straight in.'),
              icon: Icons.link_rounded,
              value: guestsJoinAutomatically,
              onChanged: onGuestsJoinAutomatically,
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// One waiting person: avatar / initials, name, member / guest, since when, Admit · Reject.
class LobbyRequestRow extends StatelessWidget {
  const LobbyRequestRow({super.key, required this.request, required this.onAdmit, required this.onReject, this.busy = false});

  final LobbyRequest request;
  final bool busy;
  final VoidCallback onAdmit;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final since = r.requestedAt == null ? '' : AppTime.time(r.requestedAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        AppAvatar(name: r.displayName, url: r.imageUrl, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 2),
            Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppBadgePill(
                r.isGuest ? t('زائر', 'Guest') : t('عضو', 'Member'),
                icon: r.isGuest ? Icons.link_rounded : Icons.school_rounded,
                color: r.isGuest ? c.warning : c.primary,
              ),
              if (since.isNotEmpty) Text(since, style: appText(11.5, c: c.textLight)),
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          IconButton(
            key: ValueKey('lobby.reject.${r.id}'),
            tooltip: t('رفض', 'Reject'),
            onPressed: onReject,
            icon: Icon(Icons.close_rounded, color: c.danger),
          ),
          IconButton.filled(
            key: ValueKey('lobby.admit.${r.id}'),
            tooltip: t('قبول', 'Admit'),
            onPressed: onAdmit,
            style: IconButton.styleFrom(backgroundColor: c.success, foregroundColor: Colors.white),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Share link sheet (meetings and any room through the generic routes)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showShareLinkSheet(BuildContext context, LiveRoomRef ref, {String? title}) =>
    showAppSheet<void>(context, (_) => ShareLinkSheet(ref: ref, title: title));

class ShareLinkSheet extends StatefulWidget {
  const ShareLinkSheet({super.key, required this.ref, this.title, this.api});

  final LiveRoomRef ref;

  /// The meeting / session title, put next to the URL when sharing.
  final String? title;
  final LiveRoomApi? api;

  @override
  State<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends State<ShareLinkSheet> {
  late final LiveRoomApi _api = widget.api ?? LiveRoomApi(widget.ref);
  bool _loading = true;
  bool _busy = false;
  String? _error;
  LiveLink? _link;
  bool _canPublish = false;
  final _maxCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _editing = false;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _maxCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _syncDraft(LiveLink? l) {
    _canPublish = l?.canPublish ?? false;
    _maxCtrl.text = l?.maxGuests?.toString() ?? '';
    _pinCtrl.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await _api.link();
      if (!mounted) return;
      _syncDraft(l);
      setState(() => _link = l);
    } catch (e) {
      if (mounted) setState(() => _error = liveRoomErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? get _draftMax {
    final v = int.tryParse(_maxCtrl.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save() async {
    if (_busy) return;
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty && !guestPinValid(pin)) {
      appToast(t('رمز الدخول من 4 إلى 8 أرقام.', 'The PIN is 4–8 digits.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final l = await _api.createLink(canPublish: _canPublish, maxGuests: _draftMax, pin: pin.isEmpty ? null : pin);
      if (!mounted) return;
      _syncDraft(l);
      setState(() {
        _link = l;
        _editing = false;
      });
      appToast(t('تم حفظ الرابط', 'Link saved'));
    } catch (e) {
      appToast(liveRoomErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (!await appConfirm(context,
        message: t('إلغاء الرابط؟ لن يعمل بعد الآن لمن يملكه.', 'Revoke the link? It stops working for everyone who has it.'),
        danger: true,
        confirmLabel: t('إلغاء الرابط', 'Revoke'))) {
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.deleteLink();
      if (!mounted) return;
      _syncDraft(null);
      setState(() {
        _link = null;
        _editing = false;
        _showQr = false;
      });
      appToast(t('أُلغي الرابط', 'Link revoked'));
    } catch (e) {
      appToast(liveRoomErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final url = _link?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    appToast(t('نُسخ الرابط', 'Link copied'));
  }

  Future<void> _share() async {
    final url = _link?.url;
    if (url == null) return;
    final name = (widget.title ?? '').trim();
    try {
      await SharePlus.instance.share(ShareParams(text: name.isEmpty ? url : '$name\n$url', subject: name.isEmpty ? null : name));
    } catch (_) {
      await _copy(); // desktop browsers without a share sheet
    }
  }

  @override
  Widget build(BuildContext context) => ShareLinkBody(
        loading: _loading,
        busy: _busy,
        error: _error,
        link: _link,
        canPublish: _canPublish,
        maxGuestsController: _maxCtrl,
        pinController: _pinCtrl,
        editing: _editing,
        showQr: _showQr,
        onRetry: _load,
        onCanPublishChanged: (v) => setState(() => _canPublish = v),
        onCreate: _save,
        onCopy: _copy,
        onShare: _share,
        onToggleQr: () => setState(() => _showQr = !_showQr),
        onToggleSettings: () => setState(() {
          _editing = !_editing;
          if (!_editing) _syncDraft(_link);
        }),
        onSaveSettings: _save,
        onRevoke: _revoke,
      );
}

/// The share-link layout (plain values).
class ShareLinkBody extends StatelessWidget {
  const ShareLinkBody({
    super.key,
    required this.loading,
    required this.busy,
    required this.error,
    required this.link,
    required this.canPublish,
    required this.maxGuestsController,
    required this.pinController,
    required this.editing,
    required this.showQr,
    required this.onRetry,
    required this.onCanPublishChanged,
    required this.onCreate,
    required this.onCopy,
    required this.onShare,
    required this.onToggleQr,
    required this.onToggleSettings,
    required this.onSaveSettings,
    required this.onRevoke,
  });

  final bool loading;
  final bool busy;
  final String? error;
  final LiveLink? link;
  final bool canPublish;
  final TextEditingController maxGuestsController;
  final TextEditingController pinController;
  final bool editing;
  final bool showQr;
  final VoidCallback onRetry;
  final ValueChanged<bool> onCanPublishChanged;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onToggleQr;
  final VoidCallback onToggleSettings;
  final VoidCallback onSaveSettings;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('رابط المشاركة', 'Share link')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              t('من يملك الرابط يطلب الانضمام باسمه — دون حساب. يدخل بعد موافقتك، أو تلقائياً إن سمحت بذلك من غرفة الانتظار.',
                  'Anyone with the link asks to join by name — no account needed. They come in after your approval, or automatically when the lobby allows it.'),
              style: appText(12.5, c: c.textMedium, h: 1.5),
            ),
            const SizedBox(height: 14),
            if (loading)
              const SizedBox(height: 220, child: AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero))
            else if (error != null)
              AppBanner(
                key: const ValueKey('share_link.error'),
                icon: Icons.error_outline_rounded,
                text: error!,
                color: c.danger,
                action: IconButton(onPressed: onRetry, icon: Icon(Icons.refresh_rounded, color: c.danger)),
              )
            else if (link == null)
              _createForm(context)
            else
              _present(context, link!),
          ]),
        ),
      ),
    ]);
  }

  Widget _options(BuildContext context, {bool hasPin = false}) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(
        key: const ValueKey('share_link.can_publish'),
        title: t('يمكنهم تشغيل الميكروفون والكاميرا', 'They can use mic and camera'),
        subtitle: t('وإلا يشاهدون ويستمعون فقط.', 'Otherwise they only watch and listen.'),
        icon: Icons.mic_rounded,
        value: canPublish,
        onChanged: busy ? null : onCanPublishChanged,
      ),
      const SizedBox(height: 6),
      AppField(
        controller: maxGuestsController,
        label: t('الحد الأقصى للزوار', 'Max guests'),
        hint: t('اتركه فارغاً بلا حد', 'Leave empty for no limit'),
        keyboard: TextInputType.number,
        ltr: true,
      ),
      AppField(
        key: const ValueKey('share_link.pin'),
        controller: pinController,
        label: hasPin ? t('رمز دخول جديد', 'New PIN') : t('رمز الدخول (اختياري)', 'PIN (optional)'),
        hint: t('4 إلى 8 أرقام', '4–8 digits'),
        keyboard: TextInputType.number,
        ltr: true,
        onChanged: (v) {
          var d = v.replaceAll(RegExp(r'[^0-9]'), '');
          if (d.length > 8) d = d.substring(0, 8);
          if (d == v) return;
          pinController.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
        },
      ),
      Text(
        hasPin
            ? t('الرمز الحالي محفوظ؛ اتركه فارغاً للإبقاء عليه.', 'The current PIN stays unless you type a new one.')
            : t('من يفتح الرابط يُسأل عن الرمز قبل طلب الانضمام.', 'Visitors are asked for the PIN before they can ask to join.'),
        style: appText(11.5, c: c.textLight, h: 1.4),
      ),
    ]);
  }

  Widget _createForm(BuildContext context) => Column(
        key: const ValueKey('share_link.create'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _options(context),
          const SizedBox(height: 10),
          AppPrimaryButton(
            key: const ValueKey('share_link.create_button'),
            label: t('إنشاء الرابط', 'Create link'),
            icon: Icons.add_link_rounded,
            busy: busy,
            onPressed: onCreate,
          ),
        ],
      );

  Widget _present(BuildContext context, LiveLink l) {
    final c = context.colors;
    final cap = l.maxGuests == null ? '∞' : '${l.maxGuests}';
    return Column(key: const ValueKey('share_link.present'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.link_rounded, size: 18, color: c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                l.url,
                key: const ValueKey('share_link.url'),
                textDirection: TextDirection.ltr,
                maxLines: 3,
                style: appText(12.5, c: c.textDark, w: FontWeight.w600),
              ),
            ),
          ]),
          if (l.hasPin) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppBadgePill(t('محمي برمز دخول', 'PIN protected'), icon: Icons.lock_rounded, color: c.warning),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppBadgePill('${t('الحد الأقصى', 'Max guests')}: $cap', icon: Icons.people_alt_rounded, color: c.primary),
        AppBadgePill(
          l.canPublish ? t('ميكروفون وكاميرا', 'Mic and camera') : t('مشاهدة واستماع فقط', 'Watch and listen only'),
          icon: l.canPublish ? Icons.mic_rounded : Icons.hearing_rounded,
          color: l.canPublish ? c.success : c.textMedium,
        ),
        if (l.createdAt != null)
          AppBadgePill('${t('أُنشئ', 'Created')}: ${AppTime.dateTime(l.createdAt!)}', icon: Icons.schedule_rounded, color: c.textMedium),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppPill(key: const ValueKey('share_link.copy'), icon: Icons.copy_rounded, label: t('نسخ', 'Copy'), onTap: busy ? null : onCopy),
        AppPill(key: const ValueKey('share_link.share'), icon: Icons.ios_share_rounded, label: t('مشاركة', 'Share'), onTap: busy ? null : onShare),
        AppPill(
          key: const ValueKey('share_link.qr'),
          icon: Icons.qr_code_2_rounded,
          label: t('رمز QR', 'QR code'),
          onTap: busy ? null : onToggleQr,
          color: showQr ? c.primary : null,
        ),
        AppPill(
          key: const ValueKey('share_link.settings'),
          icon: Icons.tune_rounded,
          label: t('الإعدادات', 'Settings'),
          onTap: busy ? null : onToggleSettings,
          color: editing ? c.primary : null,
        ),
        AppPill(key: const ValueKey('share_link.revoke'), icon: Icons.link_off_rounded, label: t('إلغاء الرابط', 'Revoke'), onTap: busy ? null : onRevoke, color: c.danger),
      ]),
      if (showQr) ...[
        const SizedBox(height: 16),
        Center(
          child: Container(
            key: const ValueKey('share_link.qr_image'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(data: l.url, version: QrVersions.auto, size: 200, backgroundColor: Colors.white),
          ),
        ),
      ],
      if (editing) ...[
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(key: const ValueKey('share_link.settings_panel'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('الإعدادات', 'Settings')),
            const SizedBox(height: 6),
            _options(context, hasPin: l.hasPin),
            const SizedBox(height: 8),
            AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: busy, onPressed: onSaveSettings),
          ]),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waiting for the host (joiner)
// ─────────────────────────────────────────────────────────────────────────────

enum WaitingState { waiting, rejected, expired }

/// Polls a waiting request until the host decides. Pops with the admitted [JoinOutcome], or with null when the
/// person cancels or the request was refused / expired (the end state is shown first; Back pops).
///
///   `final admitted = await Navigator.push<JoinOutcome>(context, MaterialPageRoute(`
///   `    builder: (_) => WaitingForHostPage(waiting: outcome, title: name)));`
class WaitingForHostPage extends StatefulWidget {
  const WaitingForHostPage({super.key, required this.waiting, this.title, this.hostName, this.poll});

  /// The `waiting` outcome of the join call (request id, secret, poll interval).
  final JoinOutcome waiting;
  final String? title;
  final String? hostName;

  /// Defaults to [LiveRoomApi.poll] (public when the outcome carries a secret, else the member poll).
  final Future<JoinOutcome> Function(JoinOutcome waiting)? poll;

  @override
  State<WaitingForHostPage> createState() => _WaitingForHostPageState();
}

class _WaitingForHostPageState extends State<WaitingForHostPage> {
  WaitingState _state = WaitingState.waiting;
  Timer? _timer;
  Timer? _lifetime;
  bool _polling = false;
  bool _done = false;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    _schedule(widget.waiting.pollAfter);
    _lifetime = Timer(kLobbyRequestLifetime, () {
      if (mounted && !_done) setState(() => _state = WaitingState.expired);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifetime?.cancel();
    super.dispose();
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _poll);
  }

  Future<void> _poll() async {
    if (_polling || _done || !mounted || _state != WaitingState.waiting) return;
    _polling = true;
    try {
      final r = await (widget.poll ?? LiveRoomApi.poll)(widget.waiting);
      if (!mounted || _done) return;
      _failures = 0;
      if (r.isAdmitted) {
        _done = true;
        Navigator.of(context).pop(r);
        return;
      }
      if (r.status == JoinStatus.rejected) {
        setState(() => _state = WaitingState.rejected);
        return;
      }
      if (r.status == JoinStatus.expired) {
        setState(() => _state = WaitingState.expired);
        return;
      }
      _schedule(r.pollAfter);
    } catch (e) {
      if (!mounted || _done) return;
      final code = liveRoomCodeText(_codeOf(e));
      if (_codeOf(e) == 'request_rejected' || _codeOf(e) == 'join_rejected') {
        setState(() => _state = WaitingState.rejected);
        return;
      }
      if (_codeOf(e) == 'request_expired' || _codeOf(e) == 'request_not_found' || _codeOf(e) == 'join_expired') {
        setState(() => _state = WaitingState.expired);
        return;
      }
      _failures++;
      if (_failures >= 20) {
        // Twenty misses in a row: the server is gone for good, say so instead of spinning forever.
        if (code != null) appToast(code, error: true);
        setState(() => _state = WaitingState.expired);
        return;
      }
      _schedule(Duration(seconds: math.min(15, 3 * _failures)));
    } finally {
      _polling = false;
    }
  }

  static String? _codeOf(Object e) => ApiException.from(e).code;

  void _leave() {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, _) {
          if (!did) _leave();
        },
        child: Scaffold(
          backgroundColor: context.colors.background,
          body: WaitingForHostScreen(
            state: _state,
            title: widget.title,
            hostName: widget.hostName,
            onCancel: _leave,
          ),
        ),
      );
}

/// The joiner's screen (plain values): an animated "Waiting for the host…" with Cancel, or the rejected / expired
/// end state with Back.
class WaitingForHostScreen extends StatefulWidget {
  const WaitingForHostScreen({super.key, required this.state, required this.onCancel, this.title, this.hostName});

  final WaitingState state;
  final String? title;
  final String? hostName;

  /// Cancel while waiting; Back on an end state.
  final VoidCallback onCancel;

  @override
  State<WaitingForHostScreen> createState() => _WaitingForHostScreenState();
}

class _WaitingForHostScreenState extends State<WaitingForHostScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final waiting = widget.state == WaitingState.waiting;
    final rejected = widget.state == WaitingState.rejected;
    final title = (widget.title ?? '').trim();
    final host = (widget.hostName ?? '').trim();
    final headline = waiting
        ? t('بانتظار المضيف…', 'Waiting for the host…')
        : rejected
            ? t('لم يُسمح لك بالدخول', 'You were not let in')
            : t('انتهت مهلة الطلب', 'The request expired');
    final body = waiting
        ? (host.isEmpty
            ? t('أُبلغ المضيف بطلبك. ستدخل فور الموافقة.', 'The host was told about you. You will be let in as soon as they approve.')
            : '${t('أُبلغ', 'We told')} $host ${t('بطلبك. ستدخل فور الموافقة.', 'about you. You will be let in as soon as they approve.')}')
        : rejected
            ? t('لم يقبل المضيف طلب الانضمام هذه المرة.', 'The host did not admit you this time.')
            : t('لم يرد المضيف خلال عشر دقائق. يمكنك طلب الانضمام مرة أخرى.', 'The host did not answer within ten minutes. You can ask to join again.');
    final color = waiting ? c.primary : (rejected ? c.danger : c.warning);
    final icon = waiting ? Icons.meeting_room_rounded : (rejected ? Icons.block_rounded : Icons.timer_off_rounded);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 150,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => CustomPaint(
                      painter: _PulsePainter(progress: waiting ? _pulse.value : 0, color: color),
                      child: child,
                    ),
                    child: Container(
                      key: ValueKey('waiting_host.${widget.state.name}'),
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
                      child: Icon(icon, size: 40, color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(headline, textAlign: TextAlign.center, style: appText(20, w: FontWeight.w800, c: c.textDark, h: 1.25)),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textMedium)),
              ],
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center, style: appText(13.5, c: c.textMedium, h: 1.5)),
              if (waiting) ...[
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) {
                        final ph = ((_pulse.value * 3) - i).clamp(0.0, 1.0);
                        final a = 0.25 + 0.75 * math.sin(ph * math.pi);
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: a)),
                        );
                      },
                    ),
                ]),
              ],
              const SizedBox(height: 28),
              AppPrimaryButton(
                key: const ValueKey('waiting_host.leave'),
                label: waiting ? t('إلغاء', 'Cancel') : t('رجوع', 'Back'),
                icon: waiting ? Icons.close_rounded : Icons.arrow_back_rounded,
                onPressed: widget.onCancel,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Two expanding rings behind the icon.
class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    for (var k = 0; k < 2; k++) {
      final p = ((progress + k * 0.5) % 1.0);
      final r = 42 + p * 40;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - p) * 0.45);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// In-room banner (host)
// ─────────────────────────────────────────────────────────────────────────────

/// "X wants to join" — Admit / Reject inline, tap the text to open the lobby. Dark glass to sit over the room.
class LobbyBanner extends StatelessWidget {
  const LobbyBanner({
    super.key,
    required this.request,
    required this.onAdmit,
    required this.onReject,
    this.onOpen,
    this.onDismiss,
    this.othersWaiting = 0,
    this.busy = false,
  });

  final LobbyRequest request;
  final VoidCallback onAdmit;
  final VoidCallback onReject;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;

  /// How many more are waiting besides [request] ("+2 more").
  final int othersWaiting;
  final bool busy;

  static const _text = Color(0xFFFFFFFF);
  static const _muted = Color(0xB3FFFFFF);
  static const _glass = Color(0xE6151A2B);
  static const _border = Color(0x33FFFFFF);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final who = r.isGuest ? t('زائر عبر الرابط', 'Guest from the link') : t('عضو', 'Member');
    final more = othersWaiting > 0 ? ' · +$othersWaiting ${t('آخرون ينتظرون', 'more waiting')}' : '';
    return Material(
      key: const ValueKey('lobby.banner'),
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          AppAvatar(name: r.displayName, url: r.imageUrl, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${r.displayName} ${t('يريد الانضمام', 'wants to join')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 13.5, fontWeight: FontWeight.w800, color: _text),
                ),
                Text(
                  '$who$more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: _muted),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _text)),
            )
          else ...[
            IconButton(
              key: const ValueKey('lobby.banner.reject'),
              tooltip: t('رفض', 'Reject'),
              onPressed: onReject,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, color: c.danger),
            ),
            IconButton.filled(
              key: const ValueKey('lobby.banner.admit'),
              tooltip: t('قبول', 'Admit'),
              onPressed: onAdmit,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: c.success, foregroundColor: Colors.white),
              icon: const Icon(Icons.check_rounded, size: 20),
            ),
          ],
          if (onDismiss != null)
            IconButton(
              key: const ValueKey('lobby.banner.dismiss'),
              tooltip: t('إخفاء', 'Hide'),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.expand_less_rounded, color: _muted, size: 20),
            ),
        ]),
      ),
    );
  }
}
