// lib/features/teacher/sessions/components/guest_link_sheet.dart
//
// "Guest link" for a live session (teacher side). One public link per session: anyone who has it joins the
// room by typing a name (and the link's PIN, when one is set), with or without mic & camera, up to an optional cap.
//
//   showGuestLinkSheet(context, sessionId: …)   → the sheet (loads GET …/guest-link; create / copy / share / QR /
//                                                  settings (mode, cap, PIN) / new link / revoke / guests joined —
//                                                  see GuestLinkApi)
//   GuestLinkBody                                → the pure layout (plain values + callbacks) so it can be tested
//                                                  with expectNoLayoutErrors in every state (test/ui/guest_live_layout_test.dart)
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
  final _pinCtrl = TextEditingController();
  bool _editing = false;
  bool _showQr = false;

  // "Guests joined" list.
  bool _joinsOpen = false;
  bool _joinsLoading = false;
  String? _joinsError;
  List<GuestJoinRecord> _joins = const [];
  int _joinsTotal = 0;

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

  void _syncDraft(GuestLink? l) {
    _canPublish = l?.canPublish ?? false;
    _maxCtrl.text = l?.maxGuests?.toString() ?? '';
    _pinCtrl.clear(); // the PIN is never sent back: an empty draft means "keep it"
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

  Future<void> _save({required bool rotate, bool clearPin = false}) async {
    if (_busy) return;
    final pin = _pinCtrl.text.trim();
    if (!clearPin && pin.isNotEmpty && !guestPinValid(pin)) {
      appToast('guest_link_pin_invalid'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final l = await GuestLinkApi.save(
        widget.sessionId,
        canPublish: _canPublish,
        maxGuests: _draftMax,
        rotate: rotate,
        pin: pin.isEmpty ? null : pin,
        clearPin: clearPin,
      );
      if (!mounted) return;
      _syncDraft(l);
      setState(() {
        _link = l;
        _editing = false;
      });
      appToast(clearPin
          ? 'guest_link_pin_removed'.tr
          : rotate
              ? 'guest_link_rotated'.tr
              : 'guest_link_saved'.tr);
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

  Future<void> _removePin() async {
    if (!await appConfirm(context, message: 'guest_link_pin_remove_confirm'.tr, confirmLabel: 'guest_link_pin_remove'.tr)) {
      return;
    }
    await _save(rotate: false, clearPin: true);
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
        _joinsOpen = false;
        _joins = const [];
        _joinsTotal = 0;
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

  // ── Guests joined ─────────────────────────────────────────────────────────
  void _toggleJoins() {
    setState(() => _joinsOpen = !_joinsOpen);
    if (_joinsOpen && _joins.isEmpty && !_joinsLoading) unawaited(_loadJoins());
  }

  Future<void> _loadJoins() async {
    if (_joinsLoading) return;
    setState(() {
      _joinsLoading = true;
      _joinsError = null;
    });
    try {
      final page = await GuestLinkApi.joins(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _joins = page.items;
        _joinsTotal = page.total;
      });
    } catch (e) {
      if (mounted) setState(() => _joinsError = guestLiveErrorText(e));
    } finally {
      if (mounted) setState(() => _joinsLoading = false);
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
        pinController: _pinCtrl,
        editing: _editing,
        showQr: _showQr,
        joinsOpen: _joinsOpen,
        joinsLoading: _joinsLoading,
        joinsError: _joinsError,
        joins: _joins,
        joinsTotal: _joinsTotal,
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
        onRemovePin: _removePin,
        onRotate: _rotate,
        onRevoke: _revoke,
        onToggleJoins: _toggleJoins,
        onRefreshJoins: _loadJoins,
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
    required this.onRemovePin,
    required this.onRotate,
    required this.onRevoke,
    required this.onToggleJoins,
    required this.onRefreshJoins,
    this.joinsOpen = false,
    this.joinsLoading = false,
    this.joinsError,
    this.joins = const [],
    this.joinsTotal = 0,
  });

  final bool loading;
  final bool busy;
  final String? error;

  /// Null → no link yet: the create form is shown.
  final GuestLink? link;

  /// Draft options (create form / settings panel).
  final bool canPublish;
  final TextEditingController maxGuestsController;

  /// New PIN draft; empty keeps the current PIN (if any).
  final TextEditingController pinController;

  /// Settings panel open under an existing link.
  final bool editing;
  final bool showQr;

  /// "Guests joined" section.
  final bool joinsOpen;
  final bool joinsLoading;
  final String? joinsError;
  final List<GuestJoinRecord> joins;
  final int joinsTotal;

  final VoidCallback onRetry;
  final ValueChanged<bool> onCanPublishChanged;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onToggleQr;
  final VoidCallback onToggleSettings;
  final VoidCallback onSaveSettings;
  final VoidCallback onRemovePin;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;
  final VoidCallback onToggleJoins;
  final VoidCallback onRefreshJoins;

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
  Widget _options(BuildContext context, {bool hasPin = false}) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      AppField(
        key: const ValueKey('guest_link.pin'),
        controller: pinController,
        label: hasPin ? 'guest_link_pin_change'.tr : 'guest_link_pin'.tr,
        hint: 'guest_link_pin_hint'.tr,
        keyboard: TextInputType.number,
        ltr: true,
        onChanged: (v) => _digitsOnly(pinController, v, max: 8),
      ),
      if (hasPin)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppPill(
            key: const ValueKey('guest_link.pin_remove'),
            icon: Icons.lock_open_rounded,
            label: 'guest_link_pin_remove'.tr,
            onTap: busy ? null : onRemovePin,
            color: c.warning,
          ),
        )
      else
        Text('guest_link_pin_sub'.tr, style: appText(11.5, c: c.textLight, h: 1.4)),
    ]);
  }

  /// Keeps a controller to digits only, [max] long (AppField has no input formatters).
  static void _digitsOnly(TextEditingController ctrl, String v, {required int max}) {
    var d = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length > max) d = d.substring(0, max);
    if (d == v) return;
    ctrl.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
  }

  // ── No link yet ───────────────────────────────────────────────────────────
  Widget _createForm(BuildContext context) => Column(
        key: const ValueKey('guest_link.create'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _options(context),
          const SizedBox(height: 10),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
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
          if (l.hasPin) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppBadgePill(
                'guest_link_pin_set'.tr,
                key: const ValueKey('guest_link.pin_chip'),
                icon: Icons.lock_rounded,
                color: c.warning,
              ),
            ),
          ],
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
        AppPill(
          key: const ValueKey('guest_link.joins'),
          icon: Icons.groups_rounded,
          label: 'guest_link_joins'.tr,
          onTap: busy ? null : onToggleJoins,
          color: joinsOpen ? c.primary : null,
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
            _options(context, hasPin: l.hasPin),
            const SizedBox(height: 8),
            AppPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, busy: busy, onPressed: onSaveSettings),
          ]),
        ),
      ],

      if (joinsOpen) ...[
        const SizedBox(height: 16),
        _JoinsPanel(
          loading: joinsLoading,
          error: joinsError,
          items: joins,
          total: joinsTotal,
          onRefresh: onRefreshJoins,
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guests joined
// ─────────────────────────────────────────────────────────────────────────────

class _JoinsPanel extends StatelessWidget {
  const _JoinsPanel({required this.loading, required this.error, required this.items, required this.total, required this.onRefresh});

  final bool loading;
  final String? error;
  final List<GuestJoinRecord> items;
  final int total;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = total > items.length ? '${'guest_link_joins'.tr} ($total)' : '${'guest_link_joins'.tr} (${items.length})';
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(key: const ValueKey('guest_link.joins_panel'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: AppSectionTitle(title)),
          IconButton(
            key: const ValueKey('guest_link.joins_refresh'),
            tooltip: 'refresh'.tr,
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh_rounded, color: c.primary),
          ),
        ]),
        if (loading && items.isEmpty)
          const SizedBox(height: 160, child: AppListSkeleton(items: 3, withAvatar: true, padding: EdgeInsets.zero))
        else if (error != null)
          AppBanner(icon: Icons.wifi_off_rounded, text: error!, color: c.danger)
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('guest_link_joins_empty'.tr, textAlign: TextAlign.center, style: appText(12.5, c: c.textLight)),
          )
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.divider),
            _JoinRow(items[i]),
          ],
      ]),
    );
  }
}

class _JoinRow extends StatelessWidget {
  const _JoinRow(this.r);

  final GuestJoinRecord r;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = r.name.trim().isEmpty ? 'guest_live_title'.tr : r.name.trim();
    final when = r.joinedAt == null ? '' : AppTime.dateTime(r.joinedAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(name: name, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 2),
            Wrap(spacing: 10, runSpacing: 2, children: [
              if (when.isNotEmpty)
                Text(when, style: appText(11.5, c: c.textMedium)),
              if (r.ipMasked != null)
                Text(r.ipMasked!, textDirection: TextDirection.ltr, style: appText(11.5, c: c.textLight)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
