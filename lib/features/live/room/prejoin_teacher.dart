// lib/features/live/room/prejoin_teacher.dart
//
// The teacher's "before you enter the room" page for a course class (Tea1Live screen=prejoin). Plain values, no
// LiveKit: PreJoinPage passes its preview, mic / camera state, devices and callbacks, exactly as it does to
// PreJoinLayout (which keeps serving the meeting host, the meeting member and the guest).
//
//   phone   header (back · "قبل تدخل الغرفة" + the class line · the waiting pill) → the preview card (the teacher's
//           own camera or the initial, "معاينة", the mic / camera round buttons) → the paper card: the live pill and
//           the time, the lesson, the camera and microphone pickers, "شكل صورتك", the recording note, the one
//           primary "ادخل الحين" and the permission hint
//   ≥ 860   the preview at the reading start, the paper card (380) at the end
//
// D-106: nothing joins until the primary button is pressed. Teacher motion: M9 on the buttons (the kit buttons),
// M10 in AppReveal; no loop on this page.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/live/live_self_view.dart' show SelfViewShape;
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart'
    show PreJoinDevice, PreJoinIssue, kPreJoinWideBreakpoint;
import 'package:flutter_education_app/features/live/room/student/student_live_parts.dart'
    show StudentLiveAvatar, StudentLiveRoundButton, StudentLiveSurface, StudentLiveTone;

/// The paper card's width on a wide window.
const double kTeacherPreJoinPanel = 380;

const double _kPreviewAspectPhone = 16 / 10;
const double _kPreviewAspectWide = 16 / 10;
const double _kPreviewAvatar = 96;

class TeacherPreJoinLayout extends StatelessWidget {
  const TeacherPreJoinLayout({
    super.key,
    required this.lessonTitle,
    required this.userName,
    required this.micOn,
    required this.camOn,
    required this.onToggleMic,
    required this.onToggleCam,
    required this.busy,
    required this.onJoin,
    required this.onBack,
    required this.joinLabel,
    this.classLine,
    this.timeLine,
    this.liveNow = false,
    this.waitingCount,
    this.preview,
    this.micLevel,
    this.issue,
    this.onRetry,
    this.mics = const [],
    this.cams = const [],
    this.selectedMic,
    this.selectedCam,
    this.onMicChanged,
    this.onCamChanged,
    this.previewShape,
    this.onPreviewShape,
    this.recordingNote = false,
    this.phoneSlot,
    this.helpButton,
    this.autofocusJoin = true,
  });

  /// The lesson ("المتتابعات الهندسية").
  final String lessonTitle;
  final String userName;

  /// The header's second line ("الرياضيات ٣ ثانوي، مجموعة أ"); null → "check your camera and microphone".
  final String? classLine;

  /// "اليوم ٧:٣٠ م" (the page formats it through AppTime); null hides the pill.
  final String? timeLine;

  /// The class has started: the red "بث مباشر" pill.
  final bool liveNow;

  /// Students already waiting at the door (the header's amber pill); null or 0 hides it. The server's lobby count,
  /// only where the page knows it.
  final int? waitingCount;
  final Widget? preview;
  final bool micOn, camOn;

  /// 0..1 while the microphone is live; null hides the meter.
  final double? micLevel;
  final VoidCallback? onToggleMic, onToggleCam;
  final bool busy;
  final VoidCallback? onJoin;
  final VoidCallback onBack;

  /// The primary button's words ("ادخل الحين" / "ادخل الاجتماع").
  final String joinLabel;
  final PreJoinIssue? issue;
  final VoidCallback? onRetry;
  final List<PreJoinDevice> mics, cams;
  final String? selectedMic, selectedCam;
  final ValueChanged<String>? onMicChanged, onCamChanged;

  /// The self-view's shape (D-092); [onPreviewShape] null hides the switch.
  final SelfViewShape? previewShape;
  final ValueChanged<SelfViewShape>? onPreviewShape;

  /// "التسجيل يبدأ أول ما تدخل…": only where the room records from the first second (never claimed otherwise).
  final bool recordingNote;

  /// The "use my phone" row (companion devices), when offered.
  final Widget? phoneSlot;

  /// The page's "i" (HelpInfoButton), when wired.
  final Widget? helpButton;
  final bool autofocusJoin;

  @override
  Widget build(BuildContext context) => AppAreaScope.role(
        role: AppRoleAccent.teacher,
        child: StudentLiveSurface(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= kPreJoinWideBreakpoint;
                final gutter = AppSpace.gutter(box.maxWidth);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.sm),
                      child: _Header(
                        classLine: classLine,
                        waitingCount: waitingCount,
                        onBack: onBack,
                        helpButton: helpButton,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(gutter, AppSpace.xs, gutter, AppSpace.lg),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
                            child: wide ? _wide(context) : _phone(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

  Widget _phone(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppReveal(index: 0, group: 'prejoin_t', child: _previewCard(_kPreviewAspectPhone)),
          const SizedBox(height: AppSpace.md),
          AppReveal(index: 1, group: 'prejoin_t', rise: AppSpace.xs, child: _paper(context)),
        ],
      );

  Widget _wide(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: AppReveal(index: 0, group: 'prejoin_t', child: _previewCard(_kPreviewAspectWide))),
          const SizedBox(width: AppSpace.lg),
          SizedBox(
            width: kTeacherPreJoinPanel,
            child: AppReveal(index: 1, group: 'prejoin_t', rise: AppSpace.xs, child: _paper(context)),
          ),
        ],
      );

  Widget _previewCard(double aspect) => TeacherPreviewCard(
        aspect: aspect,
        userName: userName,
        preview: camOn ? preview : null,
        micOn: micOn,
        camOn: camOn,
        micLevel: micLevel,
        onToggleMic: onToggleMic,
        onToggleCam: onToggleCam,
      );

  Widget _paper(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (liveNow || timeLine != null) ...[
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                if (liveNow) const _StatusPill(live: true),
                if (timeLine != null) _StatusPill(text: timeLine),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          Semantics(
            header: true,
            child: Text(
              lessonTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.headline(context).copyWith(color: c.textDark),
            ),
          ),
          if (issue != null) ...[
            const SizedBox(height: AppSpace.md),
            _IssueRow(issue: issue!, onRetry: onRetry),
          ],
          if (cams.isNotEmpty || mics.isNotEmpty || onCamChanged != null) ...[
            const SizedBox(height: AppSpace.md),
            _DeviceRow(
              fieldKey: const ValueKey('prejoin.cam'),
              icon: Icons.videocam_outlined,
              hint: 'lr_camera'.tr,
              empty: 'lr_no_camera_found'.tr,
              devices: cams,
              selected: selectedCam,
              onChanged: onCamChanged,
            ),
            const SizedBox(height: AppSpace.sm),
            _DeviceRow(
              fieldKey: const ValueKey('prejoin.mic'),
              icon: Icons.mic_none_rounded,
              hint: 'lr_microphone'.tr,
              empty: 'lr_no_mic_found'.tr,
              devices: mics,
              selected: selectedMic,
              onChanged: onMicChanged,
            ),
          ],
          if (previewShape != null && onPreviewShape != null) ...[
            const SizedBox(height: AppSpace.md),
            _ShapeRow(shape: previewShape!, onShape: onPreviewShape!),
          ],
          if (phoneSlot != null) ...[
            const SizedBox(height: AppSpace.md),
            phoneSlot!,
          ],
          if (recordingNote) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(color: set.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Icon(Icons.fiber_manual_record_outlined, size: AppIconSize.xs, color: set.ink),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('t1_lv_rec_note'.tr, style: AppType.meta(context).copyWith(color: set.ink, height: 1.5)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          KeyedSubtree(
            key: const ValueKey('prejoin.join'),
            child: AppButton.primary(
              label: busy ? 'lr_joining'.tr : joinLabel,
              icon: Icons.meeting_room_outlined,
              size: AppButtonSize.lg,
              expand: true,
              busy: busy,
              onPressed: onJoin,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            't1_lv_cam_hint'.tr,
            textAlign: TextAlign.center,
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ],
      ),
    );
  }
}

/// The preview: the camera or the glowing initial, "معاينة", and the mic / camera round buttons. Public so the
/// golden and the layout tests can pump it alone.
class TeacherPreviewCard extends StatelessWidget {
  const TeacherPreviewCard({
    super.key,
    required this.aspect,
    required this.userName,
    required this.preview,
    required this.micOn,
    required this.camOn,
    required this.onToggleMic,
    required this.onToggleCam,
    this.micLevel,
  });

  final double aspect;
  final String userName;
  final Widget? preview;
  final bool micOn, camOn;
  final double? micLevel;
  final VoidCallback? onToggleMic, onToggleCam;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.1,
            colors: [set.a.withValues(alpha: 0.75), set.heroEnd],
          ),
          border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null)
              preview!
            else
              Center(child: StudentLiveAvatar(name: userName, ring: true, size: _kPreviewAvatar)),
            PositionedDirectional(
              top: AppSpace.md,
              end: AppSpace.md,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.kit.deep.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('t1_lv_preview'.tr,
                    style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
            ),
            PositionedDirectional(
              bottom: AppSpace.md,
              start: 0,
              end: 0,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpace.sm,
                children: [
                  StudentLiveRoundButton(
                    key: const ValueKey('prejoin.mic.toggle'),
                    icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    tooltip: micOn ? 'sb_live_mic_on'.tr : 'sb_live_mic_off'.tr,
                    selected: micOn,
                    tone: micOn ? StudentLiveTone.glass : StudentLiveTone.danger,
                    onTap: onToggleMic,
                  ),
                  StudentLiveRoundButton(
                    key: const ValueKey('prejoin.cam.toggle'),
                    icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    tooltip: camOn ? 'sb_live_cam_on'.tr : 'sb_live_cam_off'.tr,
                    selected: camOn,
                    tone: camOn ? StudentLiveTone.glass : StudentLiveTone.danger,
                    onTap: onToggleCam,
                  ),
                ],
              ),
            ),
            if (micOn && micLevel != null)
              PositionedDirectional(
                top: AppSpace.md,
                start: AppSpace.md,
                child: _MicBars(level: micLevel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.classLine, required this.waitingCount, required this.onBack, this.helpButton});

  final String? classLine;
  final int? waitingCount;
  final VoidCallback onBack;
  final Widget? helpButton;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = waitingCount ?? 0;
    return Row(
      children: [
        AppIconButton(
          key: const ValueKey('prejoin.back'),
          icon: Icons.arrow_back_rounded,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onHero: true,
          onPressed: onBack,
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('t1_lv_pre_title'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
              ),
              Text(
                classLine ?? 'lr_check_devices'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.onHeroMuted),
              ),
            ],
          ),
        ),
        if (n > 0) ...[
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Container(
              key: const ValueKey('prejoin.waiting'),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(
                color: c.heroGlass,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSpace.xs,
                    height: AppSpace.xs,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.kit.warn.color),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      countText(
                        n,
                        ar1: 'طالب ينتظرك',
                        ar2: 'طالبان ينتظرانك',
                        arFew: '{n} طلاب ينتظرونك',
                        arMany: '{n} طالبًا ينتظرونك',
                        en1: '1 student is waiting',
                        en: '{n} students are waiting',
                      ).replaceAll('{n}', appDigits('$n')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ?helpButton,
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({this.live = false, this.text});

  final bool live;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = live ? c.kit.live.tint : c.kit.track;
    final ink = live ? c.kit.live.ink : c.textMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        live ? 't1_lv_live_now'.tr : text!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.fieldKey,
    required this.icon,
    required this.hint,
    required this.empty,
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  final Key fieldKey;
  final IconData icon;
  final String hint, empty;
  final List<PreJoinDevice> devices;
  final String? selected;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return AppDropdown<String>(
      key: fieldKey,
      items: [for (final d in devices) DropdownMenuItem(value: d.$1, child: Text(d.$2, maxLines: 1, overflow: TextOverflow.ellipsis))],
      value: devices.any((d) => d.$1 == selected) ? selected : null,
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
      hint: Text(devices.isEmpty ? empty : hint, maxLines: 1, overflow: TextOverflow.ellipsis),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: set.ink),
      ),
    );
  }
}

/// "شكل صورتك": rectangle / circle, the self-view's shape in the room.
class _ShapeRow extends StatelessWidget {
  const _ShapeRow({required this.shape, required this.onShape});

  final SelfViewShape shape;
  final ValueChanged<SelfViewShape> onShape;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    Widget option(SelfViewShape s, String label) {
      final on = s == shape;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('prejoin.shape.${s.name}'),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => onShape(s),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.cardBg : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: on ? AppShadow.card(context) : null,
            ),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: on ? set.ink : c.textMedium, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      children: [
        Text('t1_lv_shape'.tr, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w700)),
        Container(
          padding: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(color: c.kit.track, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: option(SelfViewShape.box, 't1_lv_shape_box'.tr)),
              Flexible(child: option(SelfViewShape.circle, 't1_lv_shape_circle'.tr)),
            ],
          ),
        ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, this.onRetry});

  final PreJoinIssue issue;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = c.kit.warn.tint;
    final ink = c.kit.warn.ink;
    return Container(
      key: const ValueKey('prejoin.issue'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(
        children: [
          Icon(issue == PreJoinIssue.permissionDenied ? Icons.lock_outline_rounded : Icons.devices_other_rounded,
              color: ink, size: AppIconSize.md),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              (issue == PreJoinIssue.permissionDenied ? 'lr_permission_denied_msg' : 'lr_no_devices_msg').tr,
              style: AppType.meta(context).copyWith(color: ink),
            ),
          ),
          if (onRetry != null)
            IconButton(
              key: const ValueKey('prejoin.retry'),
              tooltip: 'retry'.tr,
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, color: ink),
            ),
        ],
      ),
    );
  }
}

/// Five bars that rise with the voice (glass, over the preview).
class _MicBars extends StatelessWidget {
  const _MicBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = c.kit.ok.color;
    final off = c.heroGlassBorder;
    const heights = [0.45, 0.7, 1.0, 0.6, 0.85];
    return Semantics(
      label: 'lr_mic_level'.tr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(color: c.kit.deep.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, h) in heights.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.xxs / 2),
              Container(
                width: AppSpace.xxs,
                height: AppIconSize.sm * h,
                decoration: BoxDecoration(
                  color: level >= (i + 1) / (heights.length + 1) ? on : off,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
