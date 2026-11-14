// lib/features/guest/guest_live_page.dart
//
// The public landing page of a live-session guest link — route `/live/<token>` (web deep link, app link, QR).
// Works before login and in guest mode: nothing here needs an account.
//
//   GuestLivePage(token)   → loads GET /public/live/{token} (no auth), polls it every 10 s while the session has
//                            not started, remembers the typed name (SharedPreferences), and on Join calls
//                            POST …/join then opens PreJoinPage → RoomPage in guest mode.
//                            • `requires_pin` → a numeric PIN field (kept only for this page's lifetime);
//                              403 `guest_pin_invalid` → inline error + shake.
//                            • `recording_enabled` → "I understand this session may be recorded" must be ticked
//                              before Join (remembered per token in SharedPreferences).
//                            • 429 `too_many_requests` → "try again in a minute" banner with a 60 s countdown
//                              that keeps Join disabled.
//                            • `auto_join` (a DIRECT link, live-rooms-spec §10): signed in → joins with the account
//                              at once; a remembered guest name → joins at once; otherwise only the name field
//                              (autofocus) → Join. The pre-join page then waits for Join like every entry (D-106).
//                              Tried once per visit; a PIN or a missing recording consent waits for the visitor.
//   GuestLiveContent       → the pure layout (plain values + callbacks): loading skeleton · not live (waiting) ·
//                            live · error. Tested with expectNoLayoutErrors (test/ui/guest_live_layout_test.dart).
//                            Back from the room, a signed-out guest also sees the soft "create an account / sign
//                            in" card (GuestLinkCta, D-844) — never a wall. While the page is open a stray 401 never
//                            redirects to the login page (GuestLinkVisit, D-840).
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/live/room/join_args.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant_info.dart' show isGuestIdentity;
import 'package:flutter_education_app/features/sessions/teacher/model/live_response_model.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart' show WaitingForHostPage;
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_room_words.dart';
import 'package:flutter_education_app/core/guest_link_visit.dart';
import 'package:flutter_education_app/features/guest/guest_link_cta.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/design/app_icons.dart';

/// SharedPreferences key of the last name a guest typed.
const String kGuestLiveNamePref = 'guest_live_name';

/// SharedPreferences key prefix of the recording consent, one per link token.
const String kGuestLiveConsentPrefPrefix = 'guest_live_consent_';

/// How often the page re-asks the server while the session has not started.
const Duration kGuestLivePollEvery = Duration(seconds: 10);

/// How long Join stays disabled after a 429.
const Duration kGuestLiveRateLimitWait = Duration(seconds: 60);

class GuestLivePage extends StatefulWidget {
  const GuestLivePage({super.key, required this.token});

  final String token;

  @override
  State<GuestLivePage> createState() => _GuestLivePageState();
}

class _GuestLivePageState extends State<GuestLivePage> {
  /// The guest came back from the room on this page (the sign-up card shows, D-844).
  bool _backFromRoom = false;

  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController(); // in memory only: never persisted
  GuestLiveInfo? _info;
  String? _error;
  bool _errorFinal = false;
  bool _loading = true;
  bool _joining = false;
  bool _pinError = false;
  int _shakeTick = 0;
  bool _consent = false;
  int _rateLimitSeconds = 0;
  Timer? _poll;
  Timer? _rateTimer;

  /// Direct link (`auto_join`): the remembered name and consent are read; the one automatic join was tried.
  bool _prefsLoaded = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    GuestLinkVisit.enter(this);
    unawaited(_restorePrefs());
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _rateTimer?.cancel();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    GuestLinkVisit.leave(this);
    AppAssistant.release();
    super.dispose();
  }

  String get _consentKey => '$kGuestLiveConsentPrefPrefix${widget.token}';

  Future<void> _restorePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getString(kGuestLiveNamePref);
      final consent = p.getBool(_consentKey) ?? false;
      if (!mounted) return;
      setState(() {
        if (n != null && n.isNotEmpty && _nameCtrl.text.isEmpty) _nameCtrl.text = n;
        _consent = consent;
      });
    } catch (_) {}
    _prefsLoaded = true;
    _maybeAutoJoin();
  }

  /// The link's room kind (D-106): a meeting's texts say «اجتماع», a course session's «الحصة».
  LiveRoomKind get _kind => _info?.ref.kind ?? LiveRoomKind.session;

  /// A DIRECT link goes on by itself once (spec §10): with the account when signed in, else with the remembered
  /// guest name — to the pre-join page, which then waits for Join like every entry (D-106). Without a name the
  /// page shows just the name field; a PIN or the recording consent waits for the visitor too.
  void _maybeAutoJoin() {
    final info = _info;
    if (!mounted || _autoTried || !_prefsLoaded || info == null || !info.autoJoin || !info.isLive) return;
    if (_joining || _rateLimitSeconds > 0 || info.requiresPin || (info.recordingEnabled && !_consent)) return;
    final full = info.maxGuests != null && info.guestsJoined >= info.maxGuests!;
    if (full) return;
    if (_signedIn && info.signedInJoin) {
      _autoTried = true;
      unawaited(_joinWithAccount());
    } else if (_nameCtrl.text.trim().isNotEmpty) {
      _autoTried = true;
      unawaited(_join());
    }
  }

  Future<void> _rememberName(String n) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kGuestLiveNamePref, n);
    } catch (_) {}
  }

  Future<void> _setConsent(bool v) async {
    setState(() => _consent = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_consentKey, v);
    } catch (_) {}
  }

  Future<void> _load({bool first = false}) async {
    if (first && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final info = await GuestLiveApi.info(widget.token);
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
        _errorFinal = false;
      });
      _schedulePoll(info);
      _maybeAutoJoin();
    } catch (e) {
      if (!mounted) return;
      final isFinal = guestLiveErrorIsFinal(e);
      if (guestLiveErrorIsRateLimit(e)) _startRateLimit();
      setState(() {
        // A transient error during polling keeps the last good info on screen.
        if (first || _info == null || isFinal) _error = guestLiveErrorText(e, kind: _kind);
        _errorFinal = isFinal;
      });
      if (isFinal) {
        _poll?.cancel();
      } else {
        _schedulePoll(null);
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  /// Polls while the session has not started (or while the last probe failed), stops once it is live.
  /// While rate limited the next probe waits for the countdown instead.
  void _schedulePoll(GuestLiveInfo? info) {
    _poll?.cancel();
    if (info != null && info.isLive) return;
    final wait = _rateLimitSeconds > 0 ? Duration(seconds: _rateLimitSeconds + 1) : kGuestLivePollEvery;
    _poll = Timer(wait, () => _load());
  }

  // ── Rate limit countdown ──────────────────────────────────────────────────
  void _startRateLimit() {
    _rateTimer?.cancel();
    setState(() => _rateLimitSeconds = kGuestLiveRateLimitWait.inSeconds);
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _rateLimitSeconds = math.max(0, _rateLimitSeconds - 1));
      if (_rateLimitSeconds == 0) t.cancel();
    });
  }

  Future<void> _join() async {
    final info = _info;
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (info == null || _joining || _rateLimitSeconds > 0) return;
    if (name.isEmpty) {
      appToast('guest_live_name_required'.tr, error: true);
      return;
    }
    if (info.requiresPin && pin.isEmpty) {
      setState(() {
        _pinError = true;
        _shakeTick++;
      });
      return;
    }
    if (info.recordingEnabled && !_consent) {
      appToast(liveTr('guest_live_consent_required', _kind), error: true);
      return;
    }
    setState(() {
      _joining = true;
      _pinError = false;
    });
    try {
      final outcome = await GuestLiveApi.join(widget.token, name, pin: info.requiresPin ? pin : null);
      unawaited(_rememberName(name));
      if (!mounted) return;
      await _enter(info, outcome, name: name, withAccount: false);
    } catch (e) {
      if (!mounted) return;
      if (guestLiveErrorIsPin(e)) {
        setState(() {
          _pinError = true;
          _shakeTick++;
        });
        return;
      }
      if (guestLiveErrorIsRateLimit(e)) {
        _startRateLimit();
        return;
      }
      final isFinal = guestLiveErrorIsFinal(e);
      if (isFinal) {
        _poll?.cancel();
        setState(() {
          _error = guestLiveErrorText(e, kind: _kind);
          _errorFinal = true;
        });
      } else {
        appToast(guestLiveErrorText(e, kind: _kind), error: true);
        unawaited(_load()); // e.g. live_not_started / guest_limit_reached → show the fresh state
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  // ── Signed-in viewer ──────────────────────────────────────────────────────

  MyAuthProvider? get _auth {
    try {
      return context.read<MyAuthProvider>();
    } catch (_) {
      return null; // no provider above (tests / previews)
    }
  }

  bool get _signedIn => _auth?.isAuthenticated == true;

  String get _accountName => (_auth?.currentUser?.name ?? '').trim();

  /// "Join with my account": POST /api/v1/live/links/{token}/join — a member of the room joins under the member
  /// rule, anyone else as a named guest under the guest rule (live-rooms-spec §3). Same two answers as Join.
  Future<void> _joinWithAccount() async {
    final info = _info;
    if (info == null || _joining || _rateLimitSeconds > 0 || !_signedIn) return;
    if (info.recordingEnabled && !_consent) {
      appToast(liveTr('guest_live_consent_required', _kind), error: true);
      return;
    }
    setState(() => _joining = true);
    try {
      final outcome = await LiveRoomApi.joinLink(widget.token);
      if (!mounted) return;
      await _enter(info, outcome, name: _accountName.isEmpty ? _nameCtrl.text.trim() : _accountName, withAccount: true);
    } catch (e) {
      if (!mounted) return;
      if (guestLiveErrorIsRateLimit(e)) {
        _startRateLimit();
        return;
      }
      appToast(guestLiveErrorText(e, kind: _kind), error: true);
      unawaited(_load());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  /// The join answered: admitted → the pre-join page then the room; waiting → "Waiting for the host…" polls the
  /// request (public with its secret, or the member poll) until admitted; rejected / expired → told, stays here.
  Future<void> _enter(GuestLiveInfo info, JoinOutcome outcome, {required String name, required bool withAccount}) async {
    var o = outcome;
    _poll?.cancel();
    if (o.isWaiting) {
      final admitted = await Navigator.of(context).push<JoinOutcome>(
        MaterialPageRoute(
          builder: (_) => WaitingForHostPage(
            waiting: o,
            title: info.displayTitle.isNotEmpty ? info.displayTitle : liveTr('lr_live_session', info.ref.kind),
            hostName: info.displayHost,
          ),
        ),
      );
      if (!mounted) return;
      if (admitted == null) {
        unawaited(_load());
        return;
      }
      o = admitted;
    }
    if (o.isRefused) {
      appToast(liveRoomCodeText(o.status == JoinStatus.rejected ? 'join_rejected' : 'request_expired', kind: info.ref.kind) ?? '',
          error: true);
      unawaited(_load());
      return;
    }
    final j = GuestJoin.fromJson(o.payload);
    final ref = info.ref;
    final sessionId = ref.isMeeting ? ref.sessionId : (j.sessionId == 0 ? info.sessionId : j.sessionId);
    // A signed-in member joined as themselves (member identity): the room may use their token; a signed-in
    // visitor admitted as a named guest, or a plain visitor, stays in guest mode (no authenticated calls).
    final guest = !withAccount || j.identity.isEmpty || isGuestIdentity(j.identity);
    await Navigator.of(context).push(
      // No route name on purpose: a named route would be reported to the browser URL bar.
      MaterialPageRoute(
        builder: (_) => deferredPreJoin(
          args: JoinArgs(
            isTeacher: false,
            userId: guest ? -1 : (_auth?.currentUser?.id ?? -1),
            userName: name,
            sessionId: sessionId,
            roomRef: ref,
            courseId: 0,
            apiClient: ApiClient(),
            onStart: () async => LiveResponseModel(
              sessionId: sessionId,
              url: j.wsUrl,
              token: j.token,
              recordingEnabled: j.recordingEnabled,
              freeEndsAt: j.freeEndsAt,
              liveStartedAt: j.liveStartedAt,
              liveConfig: j.liveConfig,
            ),
            onEnd: () async {},
            sessionName: info.displayTitle.isNotEmpty ? info.displayTitle : null,
            guest: guest,
            canPublish: j.canPublish,
            startsAt: info.startsAt,
            hostName: info.displayHost.isEmpty ? null : info.displayHost,
          ),
        ),
      ),
    );
    // Back on this page after leaving: refresh (the session may have ended meanwhile), and offer a signed-out guest
    // the soft sign-up card (D-844).
    if (mounted) {
      setState(() => _backFromRoom = true);
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        enableFooterWidget: false,
        child: GuestLiveContent(
          signedIn: _signedIn,
          accountName: _accountName,
          onJoinWithAccount: _joinWithAccount,
          loading: _loading,
          info: _info,
          error: _error,
          errorFinal: _errorFinal,
          joining: _joining,
          nameController: _nameCtrl,
          pinController: _pinCtrl,
          pinError: _pinError,
          shakeTick: _shakeTick,
          consent: _consent,
          rateLimitSeconds: _rateLimitSeconds,
          onPinChanged: (_) {
            if (_pinError) setState(() => _pinError = false);
          },
          onConsentChanged: (v) => unawaited(_setConsent(v)),
          onJoin: _join,
          onRetry: () => _load(first: true),
          afterRoom: _backFromRoom && !_signedIn
              ? GuestLinkCta(
                  afterMeeting: true,
                  onRegister: () => openGuestSignUp(context, '/register'),
                  onSignIn: () => openGuestSignUp(context, '/login'),
                )
              : null,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Content (pure layout)
// ─────────────────────────────────────────────────────────────────────────────

class GuestLiveContent extends StatelessWidget {
  const GuestLiveContent({
    super.key,
    required this.loading,
    required this.info,
    required this.error,
    required this.joining,
    required this.nameController,
    required this.onJoin,
    required this.onRetry,
    this.errorFinal = false,
    this.pinController,
    this.pinError = false,
    this.shakeTick = 0,
    this.consent = false,
    this.rateLimitSeconds = 0,
    this.onPinChanged,
    this.onConsentChanged,
    this.signedIn = false,
    this.accountName = '',
    this.onJoinWithAccount,
    this.afterRoom,
  });

  /// Back from the room: the soft "create an account / sign in" card under the page (D-844).
  final Widget? afterRoom;

  final bool loading;
  final GuestLiveInfo? info;

  /// A signed-in viewer gets "Join with my account" next to the guest Join (when `info.signedInJoin`).
  final bool signedIn;
  final String accountName;
  final VoidCallback? onJoinWithAccount;

  /// Shown instead of the session card (null → no error).
  final String? error;

  /// The link is dead (invalid / ended / disabled): no retry button, no form.
  final bool errorFinal;
  final bool joining;
  final TextEditingController nameController;

  /// PIN field (shown when `info.requiresPin`); null → a throw-away controller.
  final TextEditingController? pinController;

  /// The last PIN was refused: red field + inline text. [shakeTick] changes to replay the shake.
  final bool pinError;
  final int shakeTick;

  /// Recording consent (required before Join when `info.recordingEnabled`).
  final bool consent;

  /// > 0 → rate limited: banner with the countdown, Join disabled.
  final int rateLimitSeconds;

  final ValueChanged<String>? onPinChanged;
  final ValueChanged<bool>? onConsentChanged;
  final VoidCallback onJoin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              AppHero(
                title: 'guest_live_title'.tr,
                subtitle: liveTr('guest_live_subtitle', info?.ref.kind ?? LiveRoomKind.session),
                icon: Icons.sensors_rounded,
              ),
              const SizedBox(height: AppSpace.xxs),
              if (loading)
                // The skeleton is a ListView: it needs a height inside this list.
                const SizedBox(height: 260, child: AppListSkeleton(items: 3, withAvatar: false))
              else if (error != null && (errorFinal || info == null))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: AppCard(
                    key: const ValueKey('guest_live.error'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AppBanner(icon: Icons.link_off_rounded, text: error!, color: c.danger),
                      if (rateLimitSeconds > 0) ...[
                        const SizedBox(height: AppSpace.sm),
                        _RateLimitBanner(seconds: rateLimitSeconds),
                      ],
                      if (!errorFinal) ...[
                        const SizedBox(height: AppSpace.sm),
                        AppPrimaryButton(
                          key: const ValueKey('guest_live.retry'),
                          label: 'retry'.tr,
                          icon: Icons.refresh_rounded,
                          onPressed: rateLimitSeconds > 0 ? null : onRetry,
                        ),
                      ],
                    ]),
                  ),
                )
              else if (info != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _SessionCard(
                    info: info!,
                    joining: joining,
                    nameController: nameController,
                    pinController: pinController,
                    pinError: pinError,
                    shakeTick: shakeTick,
                    consent: consent,
                    rateLimitSeconds: rateLimitSeconds,
                    onPinChanged: onPinChanged,
                    onConsentChanged: onConsentChanged,
                    onJoin: onJoin,
                    transientError: error,
                    signedIn: signedIn,
                    accountName: accountName,
                    onJoinWithAccount: onJoinWithAccount,
                  ),
                ),
              if (afterRoom != null && !loading) ...[
                const SizedBox(height: AppSpace.md),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: afterRoom!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required this.info,
    required this.joining,
    required this.nameController,
    required this.onJoin,
    this.pinController,
    this.pinError = false,
    this.shakeTick = 0,
    this.consent = false,
    this.rateLimitSeconds = 0,
    this.onPinChanged,
    this.onConsentChanged,
    this.transientError,
    this.signedIn = false,
    this.accountName = '',
    this.onJoinWithAccount,
  });

  final GuestLiveInfo info;
  final bool joining;
  final bool signedIn;
  final String accountName;
  final VoidCallback? onJoinWithAccount;
  final TextEditingController nameController;
  final TextEditingController? pinController;
  final bool pinError;
  final int shakeTick;
  final bool consent;
  final int rateLimitSeconds;
  final ValueChanged<String>? onPinChanged;
  final ValueChanged<bool>? onConsentChanged;
  final VoidCallback onJoin;

  /// A failed poll while the last good info is still shown.
  final String? transientError;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  /// Used when the caller passes no PIN controller (tests, previews).
  TextEditingController? _ownPin;

  TextEditingController get _pin => widget.pinController ?? (_ownPin ??= TextEditingController());

  /// Wraps the name field: a direct link focuses it at once (AppField has no autofocus of its own).
  final FocusNode _nameGroup = FocusNode(debugLabel: 'guest_live.name', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    if (widget.info.autoJoin && widget.nameController.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final n in _nameGroup.descendants) {
          if (n.canRequestFocus && !n.skipTraversal) {
            n.requestFocus();
            break;
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _ownPin?.dispose();
    _nameGroup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final info = widget.info;
    final live = info.isLive;
    final full = info.maxGuests != null && info.guestsJoined >= info.maxGuests!;
    final limited = widget.rateLimitSeconds > 0;
    final needsConsent = info.recordingEnabled && !widget.consent;
    final kind = info.ref.kind; // D-106: a meeting says «اجتماع», a course session «الحصة»
    final title = info.displayTitle.isNotEmpty ? info.displayTitle : (info.isMeeting ? t('اجتماع', 'Meeting') : 'lr_live_session'.tr);
    final host = info.displayHost;
    final accountJoin = widget.signedIn && info.signedInJoin && widget.onJoinWithAccount != null;
    // A direct link: just the title, the host and the name field — the visitor comes straight in.
    final quick = info.autoJoin;
    return AppCard(
      key: ValueKey(live ? 'guest_live.live' : 'guest_live.waiting'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Status + names
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppBadgePill(
            (live ? 'guest_live_badge_live' : 'guest_live_badge_waiting').tr,
            icon: live ? Icons.fiber_manual_record_rounded : Icons.schedule_rounded,
            color: live ? c.danger : c.warning,
          ),
          if (info.isMeeting)
            AppBadgePill(t('اجتماع', 'Meeting'), key: const ValueKey('guest_live.meeting'), icon: Icons.groups_rounded, color: c.primary),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(title, style: appText(18, w: FontWeight.w800, c: c.textDark, h: 1.2)),
        const SizedBox(height: AppSpace.xs),
        if (!quick && info.courseName.trim().isNotEmpty) AppInfoRow(Icons.menu_book_rounded, info.courseName),
        if (host.isNotEmpty) AppInfoRow(info.isMeeting ? Icons.person_rounded : Icons.school_rounded, host),
        if (!quick && info.startsAt != null) AppInfoRow(Icons.event_rounded, AppTime.dateTime(info.startsAt!)),
        AppInfoRow(
          quick || info.guestAdmission == LiveGuestAdmission.auto ? Icons.door_front_door_outlined : Icons.how_to_reg_rounded,
          quick || info.guestAdmission == LiveGuestAdmission.auto
              ? t('تدخل مباشرة بعد الانضمام', 'You come straight in after joining')
              : t('يقبل المضيف الزوار واحداً واحداً — قد تنتظر قليلاً', 'The host lets visitors in one by one — you may wait a moment'),
        ),
        if (!quick)
          AppInfoRow(
            info.canPublish ? Icons.mic_rounded : Icons.hearing_rounded,
            (info.canPublish ? 'guest_link_mode_publish' : 'guest_link_mode_listen').tr,
          ),
        if (!quick && info.maxGuests != null)
          AppInfoRow(Icons.people_alt_rounded, '${'guest_link_joined'.tr}: ${info.guestsJoined} / ${info.maxGuests}'),
        if (info.requiresPin) AppInfoRow(Icons.lock_rounded, 'guest_live_pin_protected'.tr),

        if (info.recordingEnabled) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('guest_live.recorded'),
            icon: Icons.fiber_manual_record_rounded,
            text: liveTr('lr_may_be_recorded', kind),
            color: c.danger,
          ),
        ],

        if (!live) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('guest_live.waiting_banner'),
            icon: Icons.hourglass_top_rounded,
            text: liveTr('guest_live_waiting_msg', kind),
            color: c.warning,
            action: const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ],
        if (widget.transientError != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.wifi_off_rounded, text: widget.transientError!, color: c.textMedium),
        ],
        if (live && full) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('guest_live.full'),
            icon: Icons.people_alt_rounded,
            text: liveTr('guest_live_err_limit', kind),
            color: c.warning,
          ),
        ],
        if (limited) ...[
          const SizedBox(height: AppSpace.sm),
          _RateLimitBanner(seconds: widget.rateLimitSeconds),
        ],

        const SizedBox(height: AppSpace.md),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: AppSpace.md),

        Focus(
          key: const ValueKey('guest_live.name'),
          focusNode: _nameGroup,
          child: AppField(
            controller: widget.nameController,
            label: 'guest_live_name'.tr,
            hint: 'guest_live_name_hint'.tr,
            keyboard: TextInputType.name,
          ),
        ),
        if (info.requiresPin)
          _Shake(
            tick: widget.shakeTick,
            child: Column(
              key: const ValueKey('guest_live.pin'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppField(
                  controller: _pin,
                  label: 'guest_live_pin'.tr,
                  hint: liveTr('guest_live_pin_hint', kind),
                  keyboard: TextInputType.number,
                  ltr: true,
                  onChanged: (v) {
                    var d = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (d.length > 8) d = d.substring(0, 8);
                    if (d != v) {
                      _pin.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                    }
                    widget.onPinChanged?.call(d);
                  },
                ),
                if (widget.pinError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      key: const ValueKey('guest_live.pin_error'),
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(child: Text(liveTr('guest_live_err_pin', kind), style: appText(12, c: c.danger, w: FontWeight.w600))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (info.recordingEnabled)
          _ConsentRow(
            key: const ValueKey('guest_live.consent'),
            kind: kind,
            value: widget.consent,
            onChanged: widget.joining ? null : widget.onConsentChanged,
          ),
        AppPrimaryButton(
          key: const ValueKey('guest_live.join'),
          label: widget.joining
              ? 'lr_joining'.tr
              : limited
                  ? 'guest_live_wait_s'.tr.replaceAll('{s}', '${widget.rateLimitSeconds}')
                  : live
                      ? liveTr('lr_join_session', kind)
                      : liveTr('guest_live_join_when_live', kind),
          icon: widget.joining ? null : DirIcons.login,
          busy: widget.joining,
          onPressed: live && !full && !limited && !needsConsent ? widget.onJoin : null,
        ),
        if (accountJoin) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.center,
            child: AppPill(
              key: const ValueKey('guest_live.join_account'),
              icon: Icons.account_circle_rounded,
              label: widget.accountName.isEmpty
                  ? t('الانضمام بحسابي', 'Join with my account')
                  : '${t('الانضمام بحسابي', 'Join with my account')} (${widget.accountName})',
              color: c.primary,
              onTap: live && !limited && !needsConsent && !widget.joining ? widget.onJoinWithAccount : null,
            ),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

/// "Too many attempts — try again in {s} s", counting down.
class _RateLimitBanner extends StatelessWidget {
  const _RateLimitBanner({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('guest_live.rate_limited'),
        icon: Icons.timer_outlined,
        text: 'guest_live_rate_limited_in'.tr.replaceAll('{s}', '$seconds'),
        color: context.colors.warning,
      );
}

/// "I understand this session / meeting may be recorded" — the kit has no checkbox, so a themed Material one.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({super.key, required this.value, required this.onChanged, this.kind = LiveRoomKind.session});

  final LiveRoomKind kind;

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: AppRadius.controlAll,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                key: const ValueKey('guest_live.consent_box'),
                value: value,
                activeColor: c.primary,
                side: BorderSide(color: value ? c.primary : c.textLight, width: 1.6),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(liveTr('guest_live_consent', kind), style: appText(13, c: c.textDark, h: 1.4))),
          ]),
        ),
      ),
    );
  }
}

/// Replays a short horizontal shake whenever [tick] changes.
class _Shake extends StatefulWidget {
  const _Shake({required this.tick, required this.child});

  final int tick;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant _Shake old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final t = _ctrl.value;
          final dx = t >= 1 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      );
}
