// lib/features/teacher/sessions/live/prejoin_layout.dart
//
// The pure layout of the "ready to join" screen (PreJoinPage). It knows nothing about LiveKit: it gets plain
// values + callbacks (the preview widget, mic/cam state, device lists, busy…) so it can be unit-tested with
// `expectNoLayoutErrors` at every size and language (test/ui/prejoin_layout_test.dart).
//
//   wide (≥ 860 px)  → two columns: preview card + toggles on the start side, the settings/join panel on the end side
//   phone            → one column: preview (16:9) on top, toggles, then the panel; the whole page scrolls
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
import 'package:flutter_education_app/features/shared/live/live_room.dart' show LiveRoomKind;
import 'package:flutter_education_app/features/shared/live/live_room_words.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart' show SelfViewShape;

import 'widgets/live_palette.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// One input device: `(id, label)`.
typedef PreJoinDevice = (String id, String label);

/// Why the devices are not usable (shown as a banner with a retry).
enum PreJoinIssue { permissionDenied, noDevices }

/// Width from which the two-column layout is used.
const double kPreJoinWideBreakpoint = 860;

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
          return _FadeIn(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: wide ? _wide(context) : _narrow(context),
                ),
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
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _previewColumn(context)),
        const SizedBox(width: 20),
        SizedBox(width: 380, child: _panel(context)),
      ]),
    ]);
  }

  // ── One column ────────────────────────────────────────────────────────────
  Widget _narrow(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(context),
      const SizedBox(height: 14),
      _previewColumn(context),
      const SizedBox(height: 16),
      _panel(context),
    ]);
  }

  // ── Header: back · title · role ───────────────────────────────────────────
  Widget _header(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      IconButton.filledTonal(
        key: const ValueKey('prejoin.back'),
        onPressed: onBack,
        tooltip: 'lr_go_back'.tr,
        style: IconButton.styleFrom(
          backgroundColor: c.cardBg,
          foregroundColor: c.textDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appText(18, w: FontWeight.w800, c: c.textDark, h: 1.15),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle ?? 'lr_check_devices'.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appText(12, c: c.textMedium),
          ),
        ]),
      ),
      const HelpInfoButton(pageId: 'live.prejoin'),
    ]);
  }

  // ── Preview card + mic/cam pills ──────────────────────────────────────────
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
        const SizedBox(height: 14),
        AppBanner(
          key: const ValueKey('prejoin.listen_only'),
          icon: Icons.hearing_rounded,
          text: liveTr('lr_listen_only_msg', roomKind),
        ),
      ],
      if (canPublish) ...[
      const SizedBox(height: 14),
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
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: PreJoinMicMeter(level: micLevel!),
              ),
          ]),
        ),
        const SizedBox(width: 12),
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
        const SizedBox(height: 12),
        PreJoinCameraOffHint(onTurnOn: onToggleCam),
      ],
      ],
    ]);
  }

  // ── Settings / join panel ─────────────────────────────────────────────────
  Widget _panel(BuildContext context) {
    final c = context.colors;
    final roleColor = _host ? c.primary : c.accent;
    final roleLabel = isGuest ? 'lr_guest'.tr : liveRoleLabel(host: _host, kind: roomKind);
    final roleIcon = isGuest
        ? Icons.person_outline_rounded
        : (_host ? (_meeting ? Icons.star_rounded : Icons.school_rounded) : Icons.person_rounded);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Who joins
        Row(children: [
          AppAvatar(name: userName, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(14, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppBadgePill(
                  roleLabel,
                  color: roleColor,
                  icon: roleIcon,
                ),
              ),
            ]),
          ),
        ]),
        if (canPublish) ...[
        const SizedBox(height: 14),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: 14),

        Text('lr_devices'.tr, style: appText(12.5, w: FontWeight.w800, c: c.textMedium)),
        const SizedBox(height: 10),
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
        const SizedBox(height: 12),
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
        ],

        if (issue != null) ...[
          const SizedBox(height: 14),
          AppBanner(
            key: const ValueKey('prejoin.issue'),
            icon: issue == PreJoinIssue.permissionDenied ? Icons.lock_outline_rounded : Icons.devices_other_rounded,
            text: (issue == PreJoinIssue.permissionDenied ? 'lr_permission_denied_msg' : 'lr_no_devices_msg').tr,
            color: c.warning,
            action: onRetry == null
                ? null
                : IconButton(
                    key: const ValueKey('prejoin.retry'),
                    tooltip: 'retry'.tr,
                    onPressed: onRetry,
                    icon: Icon(Icons.refresh_rounded, color: c.warning),
                  ),
          ),
        ],

        if (!_host) ...[
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 3),
              child: Icon(Icons.fiber_manual_record_rounded, size: 12, color: c.danger),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(liveTr('lr_may_be_recorded', roomKind), style: appText(12, c: c.textMedium, h: 1.4)),
            ),
          ]),
        ],

        const SizedBox(height: 18),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Join: the page's one primary action (D-106) — nothing joins until it is pressed
// ─────────────────────────────────────────────────────────────────────────────
/// The Join button: full width, filled primary, 54 high. It holds the keyboard focus ([autofocus]), so Enter presses
/// it on the web and desktop (the framework's button shortcut), and takes the focus back when it is enabled again
/// after a join that failed or was cancelled while nothing else holds the focus. On touch the focus draws nothing.
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
    final label = Flexible(
      child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: appText(15.5, w: FontWeight.w800, c: c.onHero)),
    );
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        focusNode: _focus,
        autofocus: widget.autofocus,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? c.primary.withValues(alpha: 0.4) : c.primary),
          foregroundColor: WidgetStatePropertyAll(c.onHero),
          overlayColor: WidgetStatePropertyAll(c.onHero.withValues(alpha: 0.12)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          // The keyboard focus is a clear ring (drawn in keyboard mode only).
          side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
              ? BorderSide(color: c.primaryLight, width: 3, strokeAlign: BorderSide.strokeAlignOutside)
              : BorderSide.none),
        ),
        onPressed: _enabled ? widget.onPressed : null,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (widget.busy)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onHero))
          else
            Icon(DirIcons.login, size: 20, color: c.onHero),
          const SizedBox(width: 10),
          label,
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview card: 16:9, rounded, dark; the self-view or the avatar + "camera off"
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
    final showVideo = camOn && preview != null;
    final circle = shape == SelfViewShape.circle;
    final offText = camOn
        ? 'lr_starting_camera'.tr
        : (hasCamera ? 'lr_camera_off_msg'.tr : 'lr_no_camera_found'.tr);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LivePalette.bg,
            gradient: circle && showVideo
                ? RadialGradient(radius: 0.9, colors: [LivePalette.surfaceHi, LivePalette.bg])
                : null,
            border: Border.all(color: LivePalette.ink(0.08)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (showVideo)
              // One widget tree for both shapes (only sizes and the radius change): switching never re-creates the
              // camera's renderer.
              LayoutBuilder(builder: (context, box) {
                final d = box.maxHeight * 0.8;
                return Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: circle ? d : box.maxWidth,
                    height: circle ? d : box.maxHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(circle ? d / 2 : 0),
                      border: circle ? Border.all(color: LivePalette.ink(0.78), width: 2.5) : null,
                      boxShadow: circle ? [BoxShadow(color: LivePalette.shade(0.5), blurRadius: 24, offset: const Offset(0, 8))] : null,
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
                top: 6,
                end: 6,
                child: _ShapeSwitch(shape: shape, onShape: onShape!),
              ),

            // Bottom scrim so the chips stay readable over video
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 56,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, LivePalette.shade(0.45)],
                    ),
                  ),
                ),
              ),
            ),

            // "Preview" tag
            PositionedDirectional(
              top: 10,
              start: 10,
              child: _Chip(icon: Icons.visibility_outlined, label: 'lr_preview'.tr, color: LivePalette.textHigh),
            ),

            // Mic / camera state chips
            PositionedDirectional(
              bottom: 10,
              start: 10,
              end: 10,
              child: Row(children: [
                Flexible(
                  child: _Chip(
                    icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: micOn ? 'lr_on'.tr : 'lr_muted'.tr,
                    color: micOn ? c.success : c.danger,
                  ),
                ),
                const SizedBox(width: 6),
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
          radius: 22,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? LivePalette.accent.withValues(alpha: 0.9) : Colors.transparent,
            ),
            child: Icon(icon, size: 19, color: on ? LivePalette.textHigh : LivePalette.textMid),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'lr_self_view_shape_toggle'.tr,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            option(SelfViewShape.box, Icons.crop_portrait_rounded, 'lr_self_view_box'.tr),
            const SizedBox(width: 2),
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
      // Avatar scales with the card so the column never overflows a small 16:9 box.
      final avatar = (box.maxHeight * 0.34).clamp(36.0, 88.0);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.primary.withValues(alpha: 0.22),
                border: Border.all(color: c.primary.withValues(alpha: 0.45), width: 1.5),
              ),
              child: starting
                  ? SizedBox(
                      width: avatar * 0.4,
                      height: avatar * 0.4,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: c.primaryLight),
                    )
                  : Text(
                      _initials(name),
                      style: appText(avatar * 0.36, w: FontWeight.w800, c: LivePalette.textHigh),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: appText(12, w: FontWeight.w600, c: LivePalette.ink(0.72)),
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

/// "Your camera starts off to save data" under the toggles (D-090): why the camera is off, and a quick Turn on.
class PreJoinCameraOffHint extends StatelessWidget {
  const PreJoinCameraOffHint({super.key, this.onTurnOn});

  /// Null when there is no camera to turn on (the button is hidden).
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final text = ar
        ? 'تبدأ الكاميرا مغلقة لتوفير البيانات والبطارية. شغّلها متى شئت.'
        : 'Your camera starts off to save data and battery. Turn it on whenever you like.';
    final button = ar ? 'تشغيل' : 'Turn on';
    // The primary reads on light; its light tone on dark (the deep primary sinks into a dark card).
    final tint = Theme.of(context).brightness == Brightness.dark ? c.primaryLight : c.primary;
    return Container(
      key: const ValueKey('prejoin.camera_off_hint'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.24)),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: 0.16)),
          child: Icon(Icons.data_saver_on_rounded, size: 17, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: appText(12, c: c.textMedium, h: 1.4))),
        if (onTurnOn != null) ...[
          const SizedBox(width: 4),
          TextButton.icon(
            key: const ValueKey('prejoin.camera_off_hint.turn_on'),
            onPressed: onTurnOn,
            style: TextButton.styleFrom(
              foregroundColor: tint,
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: Text(button, style: appText(12.5, w: FontWeight.w800, c: tint)),
          ),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: appText(11, w: FontWeight.w700, c: LivePalette.textHigh)),
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
        height: 6,
        child: Row(children: [
          for (var i = 0; i < segments; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
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
// Big mic / camera pill
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
    final enabled = onTap != null;
    final tone = !enabled ? c.textLight : (on ? c.primary : c.danger);
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: Material(
        color: tone.withValues(alpha: enabled ? 0.10 : 0.06),
        shape: StadiumBorder(side: BorderSide(color: tone.withValues(alpha: enabled ? 0.35 : 0.18))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled && on ? tone : tone.withValues(alpha: 0.16),
                ),
                child: Icon(on ? onIcon : offIcon, size: 20, color: enabled && on ? LivePalette.textHigh : tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: appText(13, w: FontWeight.w800, c: c.textDark)),
                  Text(
                    !enabled ? 'lr_disabled'.tr : (on ? 'lr_on'.tr : 'lr_off'.tr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(11, w: FontWeight.w600, c: tone),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The one entrance animation: a short fade.
// ─────────────────────────────────────────────────────────────────────────────
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        child: child,
        builder: (_, v, child) => Opacity(opacity: v, child: child),
      );
}
