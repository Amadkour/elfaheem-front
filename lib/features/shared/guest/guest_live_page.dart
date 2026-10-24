// lib/features/shared/guest/guest_live_page.dart
//
// The public landing page of a live-session guest link — route `/live/<token>` (web deep link, app link, QR).
// Works before login and in guest mode: nothing here needs an account.
//
//   GuestLivePage(token)   → loads GET /public/live/{token} (no auth), polls it every 10 s while the session has
//                            not started, remembers the typed name (SharedPreferences), and on Join calls
//                            POST …/join then opens PreJoinPage → RoomPage in guest mode.
//   GuestLiveContent       → the pure layout (plain values + callbacks): loading skeleton · not live (waiting) ·
//                            live · error. Tested with expectNoLayoutErrors (test/ui/guest_live_layout_test.dart).
import 'dart:async';

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

/// SharedPreferences key of the last name a guest typed.
const String kGuestLiveNamePref = 'guest_live_name';

/// How often the page re-asks the server while the session has not started.
const Duration kGuestLivePollEvery = Duration(seconds: 10);

class GuestLivePage extends StatefulWidget {
  const GuestLivePage({super.key, required this.token});

  final String token;

  @override
  State<GuestLivePage> createState() => _GuestLivePageState();
}

class _GuestLivePageState extends State<GuestLivePage> {
  final _nameCtrl = TextEditingController();
  GuestLiveInfo? _info;
  String? _error;
  bool _errorFinal = false;
  bool _loading = true;
  bool _joining = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreName());
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreName() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getString(kGuestLiveNamePref);
      if (n != null && n.isNotEmpty && mounted && _nameCtrl.text.isEmpty) _nameCtrl.text = n;
    } catch (_) {}
  }

  Future<void> _rememberName(String n) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kGuestLiveNamePref, n);
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
  void _schedulePoll(GuestLiveInfo? info) {
    _poll?.cancel();
    if (info != null && info.isLive) return;
    _poll = Timer(kGuestLivePollEvery, () => _load());
  }

  Future<void> _join() async {
    final info = _info;
    final name = _nameCtrl.text.trim();
    if (info == null || _joining) return;
    if (name.isEmpty) {
      appToast('guest_live_name_required'.tr, error: true);
      return;
    }
    setState(() => _joining = true);
    try {
      final j = await GuestLiveApi.join(widget.token, name);
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
  });

  final bool loading;
  final GuestLiveInfo? info;

  /// Shown instead of the session card (null → no error).
  final String? error;

  /// The link is dead (invalid / ended / disabled): no retry button, no form.
  final bool errorFinal;
  final bool joining;
  final TextEditingController nameController;
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
                      if (!errorFinal) ...[
                        const SizedBox(height: 12),
                        AppPrimaryButton(
                          key: const ValueKey('guest_live.retry'),
                          label: 'retry'.tr,
                          icon: Icons.refresh_rounded,
                          onPressed: onRetry,
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.info,
    required this.joining,
    required this.nameController,
    required this.onJoin,
    this.transientError,
  });

  final GuestLiveInfo info;
  final bool joining;
  final TextEditingController nameController;
  final VoidCallback onJoin;

  /// A failed poll while the last good info is still shown.
  final String? transientError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = info.isLive;
    final full = info.maxGuests != null && info.guestsJoined >= info.maxGuests!;
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
        if (transientError != null) ...[
          const SizedBox(height: 12),
          AppBanner(icon: Icons.wifi_off_rounded, text: transientError!, color: c.textMedium),
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

        const SizedBox(height: 16),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: 16),

        AppField(
          controller: nameController,
          label: 'guest_live_name'.tr,
          hint: 'guest_live_name_hint'.tr,
          keyboard: TextInputType.name,
        ),
        AppPrimaryButton(
          key: const ValueKey('guest_live.join'),
          label: joining
              ? 'lr_joining'.tr
              : live
                  ? 'lr_join_session'.tr
                  : 'guest_live_join_when_live'.tr,
          icon: joining ? null : Icons.login_rounded,
          busy: joining,
          onPressed: live && !full ? onJoin : null,
        ),
      ]),
    );
  }
}
