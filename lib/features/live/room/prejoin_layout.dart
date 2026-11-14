// lib/features/live/room/prejoin_layout.dart
//
// The pure layout of the "ready to join" screen (PreJoinPage). It knows nothing about LiveKit: it gets plain
// values + callbacks (the preview widget, mic/cam state, device lists, busy…) so it can be unit-tested with
// `expectNoLayoutErrors` at every size and language (test/ui/prejoin_layout_test.dart).
//
//   wide (≥ 860 px)  → two columns: the stage + toggles on the start side, the join block + devices on the end side
//   phone            → one column: the stage (16:9) on top, toggles, the join block, then the devices; it scrolls
//
// Warm Editorial (system.md): the dark camera stage is the page's one memorable thing (the room stays dark, video
// needs it); the person joining is a tinted block — peach for a participant or a guest, sky for the host (the role
// homes' tones) — holding their name in the editorial serif, the "may be recorded" note and the one primary action;
// the device pickers are a quiet paper card. One entrance: the stage rises, the join block follows a beat later.
//
// D-106: the page never joins by itself — the person checks the camera / microphone and presses Join, the page's
// one primary button, which holds the keyboard focus (Enter presses it on the web and desktop). Every text follows
// the room's kind ([PreJoinLayout.roomKind]): a meeting says «اجتماع» / "meeting", a course session «الحصة» /
// "session" (live_room_words.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale, AppReveal;
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomKind;
import 'package:flutter_education_app/features/live/live_room_words.dart';
import 'package:flutter_education_app/features/live/live_self_view.dart' show SelfViewShape;

import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// One input device: `(id, label)`.
typedef PreJoinDevice = (String id, String label);

/// Why the devices are not usable (shown as a banner with a retry).
enum PreJoinIssue { permissionDenied, noDevices }

/// Width from which the two-column layout is used.
const double kPreJoinWideBreakpoint = 860;

/// The end column's width on wide windows: the join block and the device card.
const double _kPanelWidth = 380;

class PreJoinLayout extends StatelessWidget {
  const PreJoinLayout({
    super.key,
    required this.title,
    required this.isTeacher,
    required this.userName,
    required this.preview,
    required this.micOn,
    required this.camOn,
    required this.onToggleMic,
    required this.onToggleCam,
    required this.mics,
    required this.cams,
    required this.selectedMic,
    required this.selectedCam,
    required this.onMicChanged,
    required this.onCamChanged,
    required this.busy,
    required this.onJoin,
    required this.onBack,
    this.issue,
    this.onRetry,
    this.phoneSlot,
    this.subtitle,
    this.isGuest = false,
    this.canPublish = true,
    this.micLevel,
    this.cameraOffHint = false,
    this.previewShape = SelfViewShape.box,
    this.onPreviewShape,
    this.roomKind = LiveRoomKind.session,
    this.isHost,
    this.autofocusJoin = true,
  });

  /// Course session or calendar meeting: picks the words («الحصة» / «الاجتماع», D-106) and the role tag.
  final LiveRoomKind roomKind;

  /// Who runs the room; null → [isTeacher]. A meeting's owner is its host without being a teacher: the role tag
  /// says Host and the "may be recorded" note is not shown to them.
  final bool? isHost;

  /// The Join button takes the keyboard focus (Enter presses it).
  final bool autofocusJoin;

  bool get _meeting => roomKind == LiveRoomKind.meeting;
  bool get _host => isHost ?? isTeacher;

  /// The self-view's shape (D-092): the preview shows the camera as the room's box will (a box fills the card, a
  /// circle sits in its middle). [onPreviewShape] null hides the shape switch.
  final SelfViewShape previewShape;
  final ValueChanged<SelfViewShape>? onPreviewShape;

  /// The camera starts off by the super admin's choice for participants (D-090): a quiet line says why and that
  /// it can be turned on.
  final bool cameraOffHint;

  /// Live microphone level 0–1 (web only); null hides the meter under the mic pill.
  final double? micLevel;

  /// Session name (or the generic "Live session").
  final String title;
  final String? subtitle;
  final bool isTeacher;

  /// A visitor from a public guest link (shown as "guest" instead of student).
  final bool isGuest;

  /// False → listen-only: no mic/cam pills and no device pickers (no tracks are created).
  final bool canPublish;
  final String userName;

  /// The live (already mirrored) self-view, or null while the camera is off / starting.
  final Widget? preview;

  final bool micOn;
  final bool camOn;

  /// Null disables the pill (no such device).
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCam;

  final List<PreJoinDevice> mics;
  final List<PreJoinDevice> cams;
  final String? selectedMic;
  final String? selectedCam;
  final ValueChanged<String> onMicChanged;
  final ValueChanged<String> onCamChanged;

  final bool busy;
  final VoidCallback? onJoin;
  final VoidCallback onBack;

  /// D-520: the "Use your phone" row (web / desktop, signed in, live.companion on); null hides it.
  final Widget? phoneSlot;

  final PreJoinIssue? issue;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= kPreJoinWideBreakpoint;
          final gutter = AppSpace.gutter(box.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.xs, gutter, AppSpace.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.content.max),
                child: wide ? _wide(context) : _narrow(context),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Two columns ───────────────────────────────────────────────────────────
  Widget _wide(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(context),
      const SizedBox(height: AppSpace.lg),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppReveal(index: 0, group: 'prejoin', child: _previewColumn(context))),
        const SizedBox(width: AppSpace.lg),
        SizedBox(
          width: _kPanelWidth,
          child: AppReveal(index: 1, group: 'prejoin', rise: AppSpace.xs, child: _panel(context)),
        ),
      ]),
    ]);
  }

  // ── One column ────────────────────────────────────────────────────────────
  Widget _narrow(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(context),
      const SizedBox(height: AppSpace.md),
      AppReveal(index: 0, group: 'prejoin', child: _previewColumn(context)),
      const SizedBox(height: AppSpace.lg),
      AppReveal(index: 1, group: 'prejoin', rise: AppSpace.xs, child: _panel(context)),
    ]);
  }

  // ── Header: back · title · help ───────────────────────────────────────────
  Widget _header(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      AppBackButton(key: const ValueKey('prejoin.back'), onPressed: onBack),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(
            subtitle ?? 'lr_check_devices'.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context),
          ),
        ]),
      ),
      const HelpInfoButton(pageId: 'live.prejoin'),
    ]);
  }

  // ── The stage + mic/cam toggles ───────────────────────────────────────────
  Widget _previewColumn(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PreJoinPreviewCard(
        preview: preview,
        camOn: camOn,
        micOn: micOn,
        hasCamera: cams.isNotEmpty,
        userName: userName,
        shape: previewShape,
        onShape: canPublish ? onPreviewShape : null,
      ),
      if (!canPublish) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          key: const ValueKey('prejoin.listen_only'),
          icon: Icons.hearing_rounded,
          text: liveTr('lr_listen_only_msg', roomKind),
        ),
      ],
      if (canPublish) ...[
        const SizedBox(height: AppSpace.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              _TogglePill(
                key: const ValueKey('prejoin.mic.toggle'),
                on: micOn,
                onIcon: Icons.mic_rounded,
                offIcon: Icons.mic_off_rounded,
                label: 'lr_microphone'.tr,
                onTap: onToggleMic,
              ),
              if (micLevel != null && micOn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                  child: PreJoinMicMeter(level: micLevel!),
                ),
            ]),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: _TogglePill(
              key: const ValueKey('prejoin.cam.toggle'),
              on: camOn,
              onIcon: Icons.videocam_rounded,
              offIcon: Icons.videocam_off_rounded,
              label: 'lr_camera'.tr,
              onTap: onToggleCam,
            ),
          ),
        ]),
        if (cameraOffHint && !camOn) ...[
          const SizedBox(height: AppSpace.sm),
          PreJoinCameraOffHint(onTurnOn: onToggleCam),
        ],
        if (phoneSlot != null) ...[
          const SizedBox(height: AppSpace.sm),
          phoneSlot!,
        ],
      ],
    ]);
  }

  // ── The join block + the device card ──────────────────────────────────────
  Widget _panel(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _joinBlock(context),
      if (canPublish) ...[
        const SizedBox(height: AppSpace.md),
        _devices(context),
      ],
    ]);
  }

  /// Who joins, as what, and Join: the host on sky, everyone else on peach (the role homes' tones).
  Widget _joinBlock(BuildContext context) {
    final c = context.colors;
    final tone = _host && !isGuest ? AppBlockTone.sky : AppBlockTone.peach;
    final bc = AppBlockColors.of(context, tone);
    final roleLabel = isGuest ? 'lr_guest'.tr : liveRoleLabel(host: _host, kind: roomKind);
    final roleIcon = isGuest
        ? Icons.person_outline_rounded
        : (_host ? (_meeting ? Icons.star_rounded : Icons.school_rounded) : Icons.person_rounded);
    return AppBlock(
      tone: tone,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _NameMark(name: userName, ink: bc.ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.section(context).copyWith(color: bc.ink),
              ),
              const SizedBox(height: AppSpace.xxs),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(roleIcon, size: AppIconSize.sm, color: bc.muted),
                const SizedBox(width: AppSpace.xxs),
                Flexible(
                  child: Text(
                    roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: bc.muted),
                  ),
                ),
              ]),
            ]),
          ),
        ]),

        if (issue != null) ...[
          const SizedBox(height: AppSpace.md),
          AppBanner(
            key: const ValueKey('prejoin.issue'),
            icon: issue == PreJoinIssue.permissionDenied ? Icons.lock_outline_rounded : Icons.devices_other_rounded,
            text: (issue == PreJoinIssue.permissionDenied ? 'lr_permission_denied_msg' : 'lr_no_devices_msg').tr,
            color: bc.accentInk(c.warning),
            action: onRetry == null
                ? null
                : IconButton(
                    key: const ValueKey('prejoin.retry'),
                    tooltip: 'retry'.tr,
                    onPressed: onRetry,
                    icon: Icon(Icons.refresh_rounded, color: bc.accentInk(c.warning)),
                  ),
          ),
        ],

        if (!_host) ...[
          const SizedBox(height: AppSpace.md),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs + AppBorder.strong),
              child: SizedBox.square(
                dimension: AppSpace.xs,
                child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: c.danger)),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                liveTr('lr_may_be_recorded', roomKind),
                style: AppType.meta(context).copyWith(color: bc.muted, height: 1.45),
              ),
            ),
          ]),
        ],

        const SizedBox(height: AppSpace.lg),
        KeyedSubtree(
          key: const ValueKey('prejoin.join'),
          child: PreJoinJoinButton(
            label: busy ? 'lr_joining'.tr : liveTr('lr_join_session', roomKind),
            busy: busy,
            onPressed: onJoin,
            autofocus: autofocusJoin,
          ),
        ),
      ]),
    );
  }

  Widget _devices(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('lr_devices'.tr, style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        AppDropdown<String>(
          key: const ValueKey('prejoin.mic'),
          items: [for (final d in mics) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
          value: mics.any((d) => d.$1 == selectedMic) ? selectedMic : null,
          onChanged: (v) {
            if (v != null) onMicChanged(v);
          },
          hint: Text(mics.isEmpty ? 'lr_no_mic_found'.tr : 'lr_microphone'.tr),
          decoration: InputDecoration(
            labelText: 'lr_microphone'.tr,
            prefixIcon: const Icon(Icons.mic_none_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppDropdown<String>(
          key: const ValueKey('prejoin.cam'),
          items: [for (final d in cams) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
          value: cams.any((d) => d.$1 == selectedCam) ? selectedCam : null,
          onChanged: (v) {
            if (v != null) onCamChanged(v);
          },
          hint: Text(cams.isEmpty ? 'lr_no_camera_found'.tr : 'lr_camera'.tr),
          decoration: InputDecoration(
            labelText: 'lr_camera'.tr,
            prefixIcon: const Icon(Icons.videocam_outlined),
          ),
        ),
      ]),
    );
  }
}

/// The joining person's initial in the editorial serif on a paper disc: a place card, not a profile photo.
class _NameMark extends StatelessWidget {
  const _NameMark({required this.name, required this.ink});

  final String name;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: AppTouch.min,
        height: AppTouch.min,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
        child: Text(
          n.isEmpty ? '?' : n.characters.first.toUpperCase(),
          style: AppType.section(context).copyWith(color: ink, height: 1),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Join: the page's one primary action (D-106) — nothing joins until it is pressed
// ─────────────────────────────────────────────────────────────────────────────
/// The Join button: full width, solid primary, 56 high (a phone's hero action, system.md §4). It holds the keyboard
/// focus ([autofocus]), so Enter presses it on the web and desktop (the framework's button shortcut), and takes the
/// focus back when it is enabled again after a join that failed or was cancelled while nothing else holds the focus.
/// Keyboard focus draws the kit's ring outside the button ([appFocusRing]); on touch the focus draws nothing. While
/// [busy] the fill stays and a spinner sits beside the label; a press scales to 0.97 (AppPressScale).
class PreJoinJoinButton extends StatefulWidget {
  const PreJoinJoinButton({super.key, required this.label, required this.onPressed, this.busy = false, this.autofocus = true});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool autofocus;

  @override
  State<PreJoinJoinButton> createState() => _PreJoinJoinButtonState();
}

class _PreJoinJoinButtonState extends State<PreJoinJoinButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'prejoin.join');

  bool get _enabled => !widget.busy && widget.onPressed != null;

  @override
  void didUpdateWidget(PreJoinJoinButton old) {
    super.didUpdateWidget(old);
    final was = !old.busy && old.onPressed != null;
    if (widget.autofocus && !was && _enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final holder = FocusManager.instance.primaryFocus;
        // Back to Join unless the person moved to another control meanwhile.
        if (mounted && _enabled && (holder == null || holder.context == null || holder is FocusScopeNode)) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = widget.busy;
    // A join in flight keeps the solid fill (the button did not go away); a button with nothing to do is the kit's
    // flat neutral well, never a washed-out primary.
    final well = !busy && widget.onPressed == null;
    final ink = well ? c.textMedium : c.onHero;
    final radius = AppRadius.controlAll;
    final button = FilledButton(
      focusNode: _focus,
      autofocus: widget.autofocus,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(well ? c.inputBg : c.primary),
        foregroundColor: WidgetStatePropertyAll(ink),
        overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed)
            ? c.primaryDark.withValues(alpha: 0.5)
            : s.contains(WidgetState.hovered)
                ? c.primaryDark.withValues(alpha: 0.22)
                : null),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: WidgetStatePropertyAll(
            well ? BorderSide(color: c.divider, width: AppBorder.hairline) : BorderSide.none),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.lg)),
        // Solid emerald (system.md §4): the theme's brand gradient stays off the one primary action.
        backgroundBuilder: (_, _, child) => child ?? const SizedBox.shrink(),
      ),
      onPressed: _enabled ? widget.onPressed : null,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (busy)
          SizedBox.square(
            dimension: AppIconSize.md,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
          )
        else
          Icon(DirIcons.login, size: AppIconSize.md, color: ink),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
      ]),
    );
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: _focus.hasFocus && _enabled && appKeyboardFocus() ? appFocusRing(context) : null,
        ),
        child: child,
      ),
      child: AppPressScale(
        scale: 0.97,
        enabled: _enabled,
        child: SizedBox(width: double.infinity, height: AppTouch.primary, child: button),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The stage: 16:9, dark (video needs it); the self-view or the initials + "camera off"
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinPreviewCard extends StatelessWidget {
  const PreJoinPreviewCard({
    super.key,
    required this.preview,
    required this.camOn,
    required this.micOn,
    required this.hasCamera,
    required this.userName,
    this.shape = SelfViewShape.box,
    this.onShape,
  });

  final Widget? preview;
  final bool camOn;
  final bool micOn;
  final bool hasCamera;
  final String userName;

  /// D-092: a box fills the card; a circle sits in its middle, as the room's self-view will look.
  final SelfViewShape shape;

  /// The Box / Circle switch on the card (top-end); null hides it.
  final ValueChanged<SelfViewShape>? onShape;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final showVideo = camOn && preview != null;
    final circle = shape == SelfViewShape.circle;
    final offText = camOn
        ? 'lr_starting_camera'.tr
        : (hasCamera ? 'lr_camera_off_msg'.tr : 'lr_no_camera_found'.tr);
    final radius = AppRadius.blockAll;
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LivePalette.bg,
            gradient: circle && showVideo
                ? RadialGradient(radius: 0.9, colors: [LivePalette.surfaceHi, LivePalette.bg])
                : null,
            border: Border.all(color: LivePalette.ink(0.08)),
            borderRadius: radius,
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (showVideo)
              // One widget tree for both shapes (only sizes and the radius change): switching never re-creates the
              // camera's renderer.
              LayoutBuilder(builder: (context, box) {
                final d = box.maxHeight * 0.8;
                return Center(
                  child: AnimatedContainer(
                    duration: motion.slow,
                    curve: AppEase.out,
                    width: circle ? d : box.maxWidth,
                    height: circle ? d : box.maxHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(circle ? d / 2 : 0),
                      border: circle ? Border.all(color: LivePalette.ink(0.78), width: AppBorder.focus) : null,
                      boxShadow: circle
                          ? [BoxShadow(color: LivePalette.shade(0.5), blurRadius: AppSpace.lg, offset: const Offset(0, AppSpace.xs))]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(circle ? d / 2 : 0),
                      child: preview!,
                    ),
                  ),
                );
              })
            else
              _CameraOff(name: userName, text: offText, starting: camOn),

            if (onShape != null && showVideo)
              PositionedDirectional(
                top: AppSpace.xs,
                end: AppSpace.xs,
                child: _ShapeSwitch(shape: shape, onShape: onShape!),
              ),

            // Bottom scrim so the chips stay readable over video
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: AppSpace.xxl + AppSpace.xs,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [LivePalette.shade(0), LivePalette.shade(0.45)],
                    ),
                  ),
                ),
              ),
            ),

            // "Preview" tag
            PositionedDirectional(
              top: AppSpace.sm,
              start: AppSpace.sm,
              child: _Chip(icon: Icons.visibility_outlined, label: 'lr_preview'.tr, color: LivePalette.textHigh),
            ),

            // Mic / camera state chips
            PositionedDirectional(
              bottom: AppSpace.sm,
              start: AppSpace.sm,
              end: AppSpace.sm,
              child: Row(children: [
                Flexible(
                  child: _Chip(
                    icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: micOn ? 'lr_on'.tr : 'lr_muted'.tr,
                    color: micOn ? c.success : c.danger,
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: _Chip(
                    icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: camOn ? 'lr_on'.tr : 'lr_off'.tr,
                    color: camOn ? c.success : c.danger,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Box / Circle on the preview card (D-092): the self-view's shape, remembered for the room.
class _ShapeSwitch extends StatelessWidget {
  const _ShapeSwitch({required this.shape, required this.onShape});

  final SelfViewShape shape;
  final ValueChanged<SelfViewShape> onShape;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    Widget option(SelfViewShape s, IconData icon, String label) {
      final on = s == shape;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          key: ValueKey('prejoin.shape.${s.name}'),
          onTap: () => onShape(s),
          radius: AppTouch.min / 2,
          child: AnimatedContainer(
            duration: motion.fast,
            curve: AppEase.out,
            width: AppSpace.xl + AppSpace.xs,
            height: AppSpace.xl + AppSpace.xs,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? LivePalette.accent.withValues(alpha: 0.9) : LivePalette.shade(0),
            ),
            child: Icon(icon, size: AppIconSize.md, color: on ? LivePalette.textHigh : LivePalette.textMid),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'lr_self_view_shape_toggle'.tr,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.xxs),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            option(SelfViewShape.box, Icons.crop_portrait_rounded, 'lr_self_view_box'.tr),
            const SizedBox(width: AppSpace.xxs),
            option(SelfViewShape.circle, Icons.circle_outlined, 'lr_self_view_circle'.tr),
          ]),
        ),
      ),
    );
  }
}

class _CameraOff extends StatelessWidget {
  const _CameraOff({required this.name, required this.text, required this.starting});

  final String name;
  final String text;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      // The mark scales with the card so the column never overflows a small 16:9 box.
      final avatar = (box.maxHeight * 0.34).clamp(AppSpace.xl + AppSpace.xxs, AppSpace.xxxl + AppSpace.lg);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.primary.withValues(alpha: 0.22),
                border: Border.all(color: c.primary.withValues(alpha: 0.45), width: AppBorder.strong),
              ),
              child: starting
                  ? SizedBox.square(
                      dimension: avatar * 0.4,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: c.primaryLight),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: EdgeInsets.all(avatar * 0.2),
                        // The initials in the editorial serif, like the join block's name mark.
                        child: Text(
                          _initials(name),
                          style: AppType.display(context).copyWith(color: LivePalette.textHigh, height: 1),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppType.label(context).copyWith(color: LivePalette.ink(0.78)),
            ),
          ]),
        ),
      );
    });
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first).toUpperCase();
  }
}

/// "Your camera starts off to save data" under the toggles (D-090): why the camera is off, and a quick Turn on. An
/// information note, so it wears the sky tone (system.md §2) at card radius.
class PreJoinCameraOffHint extends StatelessWidget {
  const PreJoinCameraOffHint({super.key, this.onTurnOn});

  /// Null when there is no camera to turn on (the button is hidden).
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bc = AppBlockColors.of(context, AppBlockTone.sky);
    final ar = AppConfig.lang == 'ar';
    final text = ar
        ? 'تبدأ الكاميرا مغلقة لتوفير البيانات والبطارية. شغّلها متى شئت.'
        : 'Your camera starts off to save data and battery. Turn it on whenever you like.';
    final button = ar ? 'تشغيل' : 'Turn on';
    return Container(
      key: const ValueKey('prejoin.camera_off_hint'),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(
        color: bc.surface,
        borderRadius: AppRadius.cardAll,
        border: bc.border == null ? null : Border.all(color: bc.border!, width: AppBorder.hairline),
      ),
      child: Row(children: [
        Icon(Icons.data_saver_on_rounded, size: AppIconSize.md, color: bc.accentInk(c.primary)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Text(text, style: AppType.meta(context).copyWith(color: bc.muted, height: 1.45)),
          ),
        ),
        if (onTurnOn != null) ...[
          const SizedBox(width: AppSpace.xxs),
          AppButton.ghost(
            key: const ValueKey('prejoin.camera_off_hint.turn_on'),
            label: button,
            icon: Icons.videocam_rounded,
            size: AppButtonSize.sm,
            onPressed: onTurnOn,
          ),
        ],
      ]),
    );
  }
}

/// A glass label over the stage.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.45),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppIconSize.xs, color: color),
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppType.overline(context).copyWith(color: LivePalette.textHigh, letterSpacing: 0)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Thin 8-segment microphone level meter (under the mic pill)
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinMicMeter extends StatelessWidget {
  const PreJoinMicMeter({super.key, required this.level, this.segments = 8});

  /// 0–1.
  final double level;
  final int segments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = (level.clamp(0.0, 1.0) * segments).round();
    return Semantics(
      key: const ValueKey('prejoin.mic.meter'),
      label: 'lr_mic_level'.tr,
      value: '${(level.clamp(0.0, 1.0) * 100).round()}%',
      child: SizedBox(
        height: AppSpace.xxs + AppBorder.focus,
        child: Row(children: [
          for (var i = 0; i < segments; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xxs),
            Expanded(
              // A live level: a 90 ms step, not a UI animation (it follows the voice).
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  color: i < lit
                      ? (i >= segments - 2 ? c.danger : (i >= segments - 4 ? c.warning : c.success))
                      : c.divider,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mic / camera toggle: a paper control with a state well
// ─────────────────────────────────────────────────────────────────────────────
class _TogglePill extends StatelessWidget {
  const _TogglePill({
    super.key,
    required this.on,
    required this.onIcon,
    required this.offIcon,
    required this.label,
    required this.onTap,
  });

  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final enabled = onTap != null;
    // On: the solid primary well with on-hero ink. Off: the danger tint, the danger icon. No device: a neutral well.
    final wellFill = !enabled ? c.inputBg : (on ? c.primary : c.dangerTint);
    final wellInk = !enabled ? c.textLight : (on ? c.onHero : appInk(context, c.danger));
    final stateInk = !enabled ? c.textMedium : appInk(context, on ? c.primary : c.danger);
    final radius = AppRadius.controlAll;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: AppPressScale(
        scale: 0.97,
        enabled: enabled,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.md, AppSpace.sm),
              child: Row(children: [
                AnimatedContainer(
                  duration: motion.fast,
                  curve: AppEase.out,
                  width: AppSpace.xl + AppSpace.xs,
                  height: AppSpace.xl + AppSpace.xs,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: wellFill),
                  child: Icon(on ? onIcon : offIcon, size: AppIconSize.md, color: wellInk),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    Text(
                      !enabled ? 'lr_disabled'.tr : (on ? 'lr_on'.tr : 'lr_off'.tr),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(color: stateInk, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
