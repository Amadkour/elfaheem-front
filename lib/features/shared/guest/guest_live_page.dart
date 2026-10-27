// lib/features/shared/guest/guest_live_page.dart
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
//   GuestLiveContent       → the pure layout (plain values + callbacks): loading skeleton · not live (waiting) ·
//                            live · error. Tested with expectNoLayoutErrors (test/ui/guest_live_layout_test.dart).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/base_page.dart';
import '../../teacher/sessions/live/prejoin.dart';
import '../../teacher/sessions/model/live_response_model.dart';
import 'guest_live_api.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant;

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

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    unawaited(_restorePrefs());
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _rateTimer?.cancel();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
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
    } catch (e) {
      if (!mounted) return;
      final isFinal = guestLiveErrorIsFinal(e);
      if (guestLiveErrorIsRateLimit(e)) _startRateLimit();
      setState(() {
        // A transient error during polling keeps the last good info on screen.
        if (first || _info == null || isFinal) _error = guestLiveErrorText(e);
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
      appToast('guest_live_consent_required'.tr, error: true);
      return;
    }
    setState(() {
      _joining = true;
      _pinError = false;
    });
    try {
      final j = await GuestLiveApi.join(widget.token, name, pin: info.requiresPin ? pin : null);
      unawaited(_rememberName(name));
      if (!mounted) return;
      _poll?.cancel();
      await Navigator.of(context).push(
        // No route name on purpose: a named route would be reported to the browser URL bar.
        MaterialPageRoute(
          builder: (_) => PreJoinPage(
            args: JoinArgs(
              isTeacher: false,
              userId: -1,
              userName: name,
              sessionId: j.sessionId == 0 ? info.sessionId : j.sessionId,
              courseId: 0,
              apiClient: ApiClient(),
              onStart: () async => LiveResponseModel(
                sessionId: j.sessionId == 0 ? info.sessionId : j.sessionId,
                url: j.wsUrl,
                token: j.token,
                recordingEnabled: j.recordingEnabled,
              ),
              onEnd: () async {},
              sessionName: info.sessionName,
              guest: true,
              canPublish: j.canPublish,
            ),
          ),
        ),
      );
      // Back on this page after leaving: refresh (the session may have ended meanwhile).
      if (mounted) unawaited(_load());
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
          _error = guestLiveErrorText(e);
          _errorFinal = true;
        });
      } else {
        appToast(guestLiveErrorText(e), error: true);
        unawaited(_load()); // e.g. live_not_started / guest_limit_reached → show the fresh state
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        enableFooterWidget: false,
        child: GuestLiveContent(
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
  });

  final bool loading;
  final GuestLiveInfo? info;

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
                subtitle: 'guest_live_subtitle'.tr,
                icon: Icons.sensors_rounded,
              ),
              const SizedBox(height: 4),
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
                        const SizedBox(height: 12),
                        _RateLimitBanner(seconds: rateLimitSeconds),
                      ],
                      if (!errorFinal) ...[
                        const SizedBox(height: 12),
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
                  ),
                ),
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
  });

  final GuestLiveInfo info;
  final bool joining;
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

  @override
  void dispose() {
    _ownPin?.dispose();
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
    final title = info.sessionName.trim().isNotEmpty ? info.sessionName : 'lr_live_session'.tr;
    return AppCard(
      key: ValueKey(live ? 'guest_live.live' : 'guest_live.waiting'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Status + names
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppBadgePill(
            (live ? 'guest_live_badge_live' : 'guest_live_badge_waiting').tr,
            icon: live ? Icons.fiber_manual_record_rounded : Icons.schedule_rounded,
            color: live ? c.danger : c.warning,
          ),
        ),
        const SizedBox(height: 10),
        Text(title, style: appText(18, w: FontWeight.w800, c: c.textDark, h: 1.2)),
        const SizedBox(height: 8),
        if (info.courseName.trim().isNotEmpty) AppInfoRow(Icons.menu_book_rounded, info.courseName),
        if (info.teacherName.trim().isNotEmpty) AppInfoRow(Icons.school_rounded, info.teacherName),
        AppInfoRow(
          info.canPublish ? Icons.mic_rounded : Icons.hearing_rounded,
          (info.canPublish ? 'guest_link_mode_publish' : 'guest_link_mode_listen').tr,
        ),
        if (info.maxGuests != null)
          AppInfoRow(Icons.people_alt_rounded, '${'guest_link_joined'.tr}: ${info.guestsJoined} / ${info.maxGuests}'),
        if (info.requiresPin) AppInfoRow(Icons.lock_rounded, 'guest_live_pin_protected'.tr),

        if (info.recordingEnabled) ...[
          const SizedBox(height: 12),
          AppBanner(
            key: const ValueKey('guest_live.recorded'),
            icon: Icons.fiber_manual_record_rounded,
            text: 'lr_may_be_recorded'.tr,
            color: c.danger,
          ),
        ],

        if (!live) ...[
          const SizedBox(height: 12),
          AppBanner(
            key: const ValueKey('guest_live.waiting_banner'),
            icon: Icons.hourglass_top_rounded,
            text: 'guest_live_waiting_msg'.tr,
            color: c.warning,
            action: const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ],
        if (widget.transientError != null) ...[
          const SizedBox(height: 12),
          AppBanner(icon: Icons.wifi_off_rounded, text: widget.transientError!, color: c.textMedium),
        ],
        if (live && full) ...[
          const SizedBox(height: 12),
          AppBanner(
            key: const ValueKey('guest_live.full'),
            icon: Icons.people_alt_rounded,
            text: 'guest_live_err_limit'.tr,
            color: c.warning,
          ),
        ],
        if (limited) ...[
          const SizedBox(height: 12),
          _RateLimitBanner(seconds: widget.rateLimitSeconds),
        ],

        const SizedBox(height: 16),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: 16),

        AppField(
          controller: widget.nameController,
          label: 'guest_live_name'.tr,
          hint: 'guest_live_name_hint'.tr,
          keyboard: TextInputType.name,
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
                  hint: 'guest_live_pin_hint'.tr,
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
                        const SizedBox(width: 6),
                        Expanded(child: Text('guest_live_err_pin'.tr, style: appText(12, c: c.danger, w: FontWeight.w600))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (info.recordingEnabled)
          _ConsentRow(
            key: const ValueKey('guest_live.consent'),
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
                      ? 'lr_join_session'.tr
                      : 'guest_live_join_when_live'.tr,
          icon: widget.joining ? null : Icons.login_rounded,
          busy: widget.joining,
          onPressed: live && !full && !limited && !needsConsent ? widget.onJoin : null,
        ),
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

/// "I understand this session may be recorded" — the kit has no checkbox, so a themed Material one.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('guest_live_consent'.tr, style: appText(13, c: c.textDark, h: 1.4))),
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
