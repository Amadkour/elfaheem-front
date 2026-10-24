// lib/features/teacher/sessions/components/guest_link_sheet.dart
//
// "Guest link" for a live session (teacher side). One public link per session: anyone who has it joins the
// room by typing a name, with or without mic & camera, up to an optional cap.
//
//   showGuestLinkSheet(context, sessionId: …)   → the sheet (loads GET …/guest-link; create / copy / share / QR /
//                                                  settings / new link / revoke — see GuestLinkApi)
//   GuestLinkBody                                → the pure layout (plain values + callbacks) so it can be tested
//                                                  with expectNoLayoutErrors in both states (test/ui/guest_live_layout_test.dart)
//
// Wrap the entry action in ParentComponent(featureKey: 'live.guest_link') so the super admin can switch it off.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_kit.dart';
import '../../../shared/guest/guest_live_api.dart';

/// Kill-switch id of the whole feature (teacher action + sheet).
const String kGuestLinkFeatureKey = 'live.guest_link';

Future<void> showGuestLinkSheet(BuildContext context, {required int sessionId, String? sessionName}) =>
    showAppSheet<void>(context, (_) => GuestLinkSheet(sessionId: sessionId, sessionName: sessionName));

// ─────────────────────────────────────────────────────────────────────────────
// Sheet (state + API)
// ─────────────────────────────────────────────────────────────────────────────

class GuestLinkSheet extends StatefulWidget {
  const GuestLinkSheet({super.key, required this.sessionId, this.sessionName});

  final int sessionId;
  final String? sessionName;

  @override
  State<GuestLinkSheet> createState() => _GuestLinkSheetState();
}

class _GuestLinkSheetState extends State<GuestLinkSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  GuestLink? _link;

  // Draft options (create form, and the settings panel of an existing link).
  bool _canPublish = false;
  final _maxCtrl = TextEditingController();
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
    super.dispose();
  }

  void _syncDraft(GuestLink? l) {
    _canPublish = l?.canPublish ?? false;
    _maxCtrl.text = l?.maxGuests?.toString() ?? '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await GuestLinkApi.load(widget.sessionId);
      if (!mounted) return;
      _syncDraft(l);
      setState(() => _link = l);
    } catch (e) {
      if (mounted) setState(() => _error = guestLiveErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? get _draftMax {
    final v = int.tryParse(_maxCtrl.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save({required bool rotate}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final l = await GuestLinkApi.save(widget.sessionId, canPublish: _canPublish, maxGuests: _draftMax, rotate: rotate);
      if (!mounted) return;
      _syncDraft(l);
      setState(() {
        _link = l;
        _editing = false;
      });
      appToast(rotate ? 'guest_link_rotated'.tr : 'guest_link_saved'.tr);
    } catch (e) {
      appToast(guestLiveErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    if (!await appConfirm(context, message: 'guest_link_rotate_confirm'.tr, confirmLabel: 'guest_link_new'.tr)) return;
    await _save(rotate: true);
  }

  Future<void> _revoke() async {
    if (!await appConfirm(context, message: 'guest_link_revoke_confirm'.tr, danger: true, confirmLabel: 'guest_link_revoke'.tr)) {
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await GuestLinkApi.revoke(widget.sessionId);
      if (!mounted) return;
      _syncDraft(null);
      setState(() {
        _link = null;
        _editing = false;
        _showQr = false;
      });
      appToast('guest_link_revoked'.tr);
    } catch (e) {
      appToast(guestLiveErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final url = _link?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    appToast('guest_link_copied'.tr);
  }

  Future<void> _share() async {
    final url = _link?.url;
    if (url == null) return;
    final name = (widget.sessionName ?? '').trim();
    try {
      await SharePlus.instance.share(ShareParams(text: name.isEmpty ? url : '$name\n$url', subject: name.isEmpty ? null : name));
    } catch (_) {
      await _copy(); // desktop browsers without a share sheet
    }
  }

  @override
  Widget build(BuildContext context) => GuestLinkBody(
        loading: _loading,
        busy: _busy,
        error: _error,
        link: _link,
        canPublish: _canPublish,
        maxGuestsController: _maxCtrl,
        editing: _editing,
        showQr: _showQr,
        onRetry: _load,
        onCanPublishChanged: (v) => setState(() => _canPublish = v),
        onCreate: () => _save(rotate: false),
        onCopy: _copy,
        onShare: _share,
        onToggleQr: () => setState(() => _showQr = !_showQr),
        onToggleSettings: () => setState(() {
          _editing = !_editing;
          if (!_editing) _syncDraft(_link); // cancelled: drop the draft
        }),
        onSaveSettings: () => _save(rotate: false),
        onRotate: _rotate,
        onRevoke: _revoke,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Body (pure layout)
// ─────────────────────────────────────────────────────────────────────────────

class GuestLinkBody extends StatelessWidget {
  const GuestLinkBody({
    super.key,
    required this.loading,
    required this.busy,
    required this.error,
    required this.link,
    required this.canPublish,
    required this.maxGuestsController,
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
    required this.onRotate,
    required this.onRevoke,
  });

  final bool loading;
  final bool busy;
  final String? error;

  /// Null → no link yet: the create form is shown.
  final GuestLink? link;

  /// Draft options (create form / settings panel).
  final bool canPublish;
  final TextEditingController maxGuestsController;

  /// Settings panel open under an existing link.
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
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader('guest_link_title'.tr),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('guest_link_intro'.tr, style: appText(12.5, c: c.textMedium, h: 1.5)),
            const SizedBox(height: 14),
            if (loading)
              // The skeleton is a ListView: it needs a height inside this scroll view.
              const SizedBox(height: 240, child: AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero))
            else if (error != null)
              AppBanner(
                key: const ValueKey('guest_link.error'),
                icon: Icons.error_outline_rounded,
                text: error!,
                color: c.danger,
                action: IconButton(
                  key: const ValueKey('guest_link.retry'),
                  tooltip: 'retry'.tr,
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh_rounded, color: c.danger),
                ),
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

  // ── Options (shared by the create form and the settings panel) ───────────
  Widget _options(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
          key: const ValueKey('guest_link.can_publish'),
          title: 'guest_link_can_publish'.tr,
          subtitle: 'guest_link_can_publish_sub'.tr,
          icon: Icons.mic_rounded,
          value: canPublish,
          onChanged: busy ? null : onCanPublishChanged,
        ),
        const SizedBox(height: 6),
        AppField(
          controller: maxGuestsController,
          label: 'guest_link_max'.tr,
          hint: 'guest_link_max_hint'.tr,
          keyboard: TextInputType.number,
          ltr: true,
        ),
      ]);

  // ── No link yet ───────────────────────────────────────────────────────────
  Widget _createForm(BuildContext context) => Column(
        key: const ValueKey('guest_link.create'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _options(context),
          const SizedBox(height: 6),
          AppPrimaryButton(
            label: 'guest_link_create'.tr,
            icon: Icons.add_link_rounded,
            busy: busy,
            onPressed: onCreate,
          ),
        ],
      );

  // ── Link present ──────────────────────────────────────────────────────────
  Widget _present(BuildContext context, GuestLink l) {
    final c = context.colors;
    final cap = l.maxGuests == null ? '∞' : '${l.maxGuests}';
    return Column(key: const ValueKey('guest_link.present'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // URL box
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider),
        ),
        child: Row(children: [
          Icon(Icons.link_rounded, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              l.url,
              key: const ValueKey('guest_link.url'),
              textDirection: TextDirection.ltr,
              maxLines: 3,
              style: appText(12.5, c: c.textDark, w: FontWeight.w600),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // Facts
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppBadgePill(
          '${'guest_link_joined'.tr}: ${l.guestsJoined} / $cap',
          icon: Icons.people_alt_rounded,
          color: c.primary,
        ),
        AppBadgePill(
          (l.canPublish ? 'guest_link_mode_publish' : 'guest_link_mode_listen').tr,
          icon: l.canPublish ? Icons.mic_rounded : Icons.hearing_rounded,
          color: l.canPublish ? c.success : c.textMedium,
        ),
        if (l.createdAt != null)
          AppBadgePill(
            '${'guest_link_created'.tr}: ${AppTime.dateTime(l.createdAt!)}',
            icon: Icons.schedule_rounded,
            color: c.textMedium,
          ),
      ]),
      const SizedBox(height: 14),

      // Actions
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppPill(key: const ValueKey('guest_link.copy'), icon: Icons.copy_rounded, label: 'guest_link_copy'.tr, onTap: busy ? null : onCopy),
        AppPill(key: const ValueKey('guest_link.share'), icon: Icons.ios_share_rounded, label: 'guest_link_share'.tr, onTap: busy ? null : onShare),
        AppPill(
          key: const ValueKey('guest_link.qr'),
          icon: Icons.qr_code_2_rounded,
          label: 'guest_link_qr'.tr,
          onTap: busy ? null : onToggleQr,
          color: showQr ? c.primary : null,
        ),
        AppPill(
          key: const ValueKey('guest_link.settings'),
          icon: Icons.tune_rounded,
          label: 'settings'.tr,
          onTap: busy ? null : onToggleSettings,
          color: editing ? c.primary : null,
        ),
        AppPill(key: const ValueKey('guest_link.rotate'), icon: Icons.autorenew_rounded, label: 'guest_link_new'.tr, onTap: busy ? null : onRotate, color: c.warning),
        AppPill(key: const ValueKey('guest_link.revoke'), icon: Icons.link_off_rounded, label: 'guest_link_revoke'.tr, onTap: busy ? null : onRevoke, color: c.danger),
      ]),

      if (showQr) ...[
        const SizedBox(height: 16),
        Center(
          child: Container(
            key: const ValueKey('guest_link.qr_image'),
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
          child: Column(key: const ValueKey('guest_link.settings_panel'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle('settings'.tr),
            const SizedBox(height: 6),
            _options(context),
            const SizedBox(height: 4),
            AppPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, busy: busy, onPressed: onSaveSettings),
          ]),
        ),
      ],
    ]);
  }
}
