// lib/features/live/room/prejoin_student.dart
//
// The student's "ready to join?" page for a course class (Stu1Learn screen=prejoin). Plain values, no LiveKit: the
// PreJoinPage passes its preview, mic / camera state and callbacks, exactly as it does to PreJoinLayout, which keeps
// serving the teacher, the meeting and the guest.
//
//   phone   the header (back · "جاهز تدخل؟" + the class line · "بدأت من ١٢ د") → the self card ("أنت", the initial or
//           the camera, the voice meter) → mic / camera with their words → the class card (the teacher breathing (M8),
//           "الحصة شغّالة", "lesson مع teacher", the hot "ادخل الحصة", "تدخل باسمك: …")
//   ≥ 860   the self card + controls at the reading start, the class card (380) at the end
//
// Privacy (DESIGN_SYSTEM §1.2): the page shows the teacher and the student, never a count of who is inside.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart'
    show PreJoinDevice, PreJoinIssue, kPreJoinWideBreakpoint;
import 'package:flutter_education_app/features/live/room/student/student_live_parts.dart';

/// The class card's width on a wide window.
const double kStudentPreJoinPanel = 380;

/// The self card's shape.
const double _kSelfAspectPhone = 16 / 9;
const double _kSelfAspectWide = 4 / 3;

/// The avatar in the self card and the teacher's in the class card.
const double _kSelfAvatar = 96;
const double _kTeacherAvatar = 78;

class StudentPreJoinLayout extends StatelessWidget {
  const StudentPreJoinLayout({
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
    this.teacherName,
    this.classLine,
    this.startedMinutes,
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
    this.phoneSlot,
  });

  /// The lesson ("الدوال الأسية"); the class card reads "lesson مع teacher".
  final String lessonTitle;
  final String? teacherName;
  final String userName;

  /// The header's second line ("الرياضيات، حصة مباشرة"); null → "حصة مباشرة".
  final String? classLine;

  /// Minutes since the class started (the pill); null hides it.
  final int? startedMinutes;

  /// The camera preview (LiveVideoView) while the camera is on.
  final Widget? preview;
  final bool micOn, camOn;

  /// 0..1 while the microphone is live; null hides the meter.
  final double? micLevel;
  final VoidCallback? onToggleMic, onToggleCam;
  final bool busy;
  final VoidCallback? onJoin;
  final VoidCallback onBack;
  final PreJoinIssue? issue;
  final VoidCallback? onRetry;
  final List<PreJoinDevice> mics, cams;
  final String? selectedMic, selectedCam;
  final ValueChanged<String>? onMicChanged, onCamChanged;

  /// The "use my phone" row (companion devices), when offered.
  final Widget? phoneSlot;

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
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
                      child: _Header(classLine: classLine, startedMinutes: startedMinutes, onBack: onBack),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(gutter, AppSpace.xs, gutter, AppSpace.lg),
                        child: wide ? _wide(context) : _phone(context),
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
          _selfCard(_kSelfAspectPhone),
          const SizedBox(height: AppSpace.md),
          _controls(context),
          const SizedBox(height: AppSpace.lg),
          _classCard(),
        ],
      );

  Widget _wide(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _selfCard(_kSelfAspectWide),
                const SizedBox(height: AppSpace.md),
                _controls(context),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          SizedBox(width: kStudentPreJoinPanel, child: _classCard()),
        ],
      );

  Widget _selfCard(double aspect) => _SelfCard(
        aspect: aspect,
        userName: userName,
        preview: camOn ? preview : null,
        micOn: micOn,
        micLevel: micLevel,
      );

  Widget _controls(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpace.lg,
          runSpacing: AppSpace.sm,
          children: [
            StudentLiveRoundButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: micOn ? 'sb_live_mic_on'.tr : 'sb_live_mic_off'.tr,
              label: micOn ? 'sb_live_mic_on'.tr : 'sb_live_mic_off'.tr,
              selected: micOn,
              tone: micOn ? StudentLiveTone.glass : StudentLiveTone.danger,
              onTap: onToggleMic,
            ),
            StudentLiveRoundButton(
              icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              tooltip: camOn ? 'sb_live_cam_on'.tr : 'sb_live_cam_off'.tr,
              label: camOn ? 'sb_live_cam_on'.tr : 'sb_live_cam_off'.tr,
              selected: camOn,
              tone: camOn ? StudentLiveTone.glass : StudentLiveTone.danger,
              onTap: onToggleCam,
            ),
          ],
        ),
        if (mics.length + cams.length > 2 && (onMicChanged != null || onCamChanged != null)) ...[
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(
            onPressed: () => _pickDevices(context),
            style: TextButton.styleFrom(foregroundColor: c.onHero, minimumSize: const Size(0, AppTouch.min)),
            icon: const Icon(Icons.volume_up_rounded, size: AppIconSize.sm),
            label: Text('sb_live_devices'.tr, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
          ),
        ],
        if (issue != null) ...[
          const SizedBox(height: AppSpace.sm),
          _IssueRow(issue: issue!, onRetry: onRetry),
        ],
        if (phoneSlot != null) ...[
          const SizedBox(height: AppSpace.sm),
          phoneSlot!,
        ],
      ],
    );
  }

  Future<void> _pickDevices(BuildContext context) => showAppSheet<void>(
        context,
        (ctx) => AppSheetContent(
          title: 'sb_live_devices'.tr,
          icon: Icons.tune_rounded,
          children: [
            if (mics.isNotEmpty) ...[
              _SheetLabel('lr_microphone'.tr),
              for (final d in mics)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: AppTile(
                    dense: true,
                    icon: Icons.mic_rounded,
                    title: d.$2,
                    selected: d.$1 == selectedMic,
                    onTap: () {
                      onMicChanged?.call(d.$1);
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                ),
            ],
            if (cams.isNotEmpty) ...[
              _SheetLabel('lr_camera'.tr),
              for (final d in cams)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: AppTile(
                    dense: true,
                    icon: Icons.videocam_rounded,
                    title: d.$2,
                    selected: d.$1 == selectedCam,
                    onTap: () {
                      onCamChanged?.call(d.$1);
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                ),
            ],
          ],
        ),
      );

  Widget _classCard() => StudentClassCard(
        lessonTitle: lessonTitle,
        teacherName: teacherName,
        userName: userName,
        busy: busy,
        onJoin: onJoin,
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.classLine, required this.startedMinutes, required this.onBack});

  final String? classLine;
  final int? startedMinutes;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        AppIconButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onHero: true, onPressed: onBack),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('sb_live_ready'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
              ),
              Text(
                classLine ?? 'sb_live_live_class'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.onHeroMuted),
              ),
            ],
          ),
        ),
        if (startedMinutes != null) ...[
          const SizedBox(width: AppSpace.sm),
          Flexible(child: StudentLiveStartedPill(minutes: startedMinutes!)),
        ],
      ],
    );
  }
}

class _SelfCard extends StatelessWidget {
  const _SelfCard({required this.aspect, required this.userName, required this.preview, required this.micOn, this.micLevel});

  final double aspect;
  final String userName;
  final Widget? preview;
  final bool micOn;
  final double? micLevel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.block),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [c.kit.accent(AppAccent.grape).color.withValues(alpha: 0.35), set.heroEnd],
          ),
          border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null)
              preview!
            else
              Center(child: StudentLiveAvatar(name: userName, self: true, ring: true, size: _kSelfAvatar)),
            PositionedDirectional(
              top: AppSpace.md,
              end: AppSpace.md,
              child: _GlassPill(child: Text('sb_live_you'.tr,
                  style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))),
            ),
            PositionedDirectional(
              bottom: AppSpace.md,
              end: AppSpace.md,
              child: _GlassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(micOn ? Icons.mic_none_rounded : Icons.mic_off_rounded, size: AppIconSize.sm, color: c.onHero),
                    if (micOn && micLevel != null) ...[
                      const SizedBox(width: AppSpace.xs),
                      _LevelBars(level: micLevel!),
                    ],
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      micOn ? 'sb_live_voice_ok'.tr : 'sb_live_mic_off'.tr,
                      style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: context.colors.kit.deep.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: child,
      );
}

/// Five bars that rise with the voice.
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final on = context.colors.kit.ok.color;
    final off = context.colors.heroGlassBorder;
    const heights = [0.45, 0.7, 1.0, 0.6, 0.85];
    return Semantics(
      label: 'lr_mic_level'.tr,
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
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: c.onHero, size: AppIconSize.md),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              (issue == PreJoinIssue.permissionDenied ? 'lr_permission_denied_msg' : 'lr_no_devices_msg').tr,
              style: AppType.meta(context).copyWith(color: c.onHero),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: c.onHero),
              child: Text('retry'.tr),
            ),
        ],
      ),
    );
  }
}

/// The class card: the teacher breathing (M8), "الحصة شغّالة", "lesson مع teacher", the hot join button and
/// "تدخل باسمك: …". Public: the golden and layout tests pump it alone.
class StudentClassCard extends StatelessWidget {
  const StudentClassCard({
    super.key,
    required this.lessonTitle,
    required this.userName,
    required this.busy,
    required this.onJoin,
    this.teacherName,
  });

  final String lessonTitle;
  final String? teacherName;
  final String userName;
  final bool busy;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final teacher = (teacherName ?? '').trim();
    final line = teacher.isEmpty ? lessonTitle : sbLiveTr('sb_live_with', {'lesson': lessonTitle, 'teacher': teacher});
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      decoration: BoxDecoration(
        color: c.kit.deep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Column(
        children: [
          AppBreathe(
            color: c.kit.warmOnDark,
            child: StudentLiveAvatar(name: teacher.isEmpty ? lessonTitle : teacher, size: _kTeacherAvatar),
          ),
          const SizedBox(height: AppSpace.md),
          Text('sb_live_class_on'.tr, style: AppType.kicker(context).copyWith(color: c.kit.warmOnDark)),
          const SizedBox(height: AppSpace.xs),
          Text(
            line,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.headline(context).copyWith(color: c.onHero),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton.hot(
            label: 'sb_live_join'.tr,
            trailingIcon: Icons.arrow_forward_rounded,
            size: AppButtonSize.lg,
            expand: true,
            busy: busy,
            onPressed: onJoin,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            sbLiveTr('sb_live_as', {'name': userName}),
            textAlign: TextAlign.center,
            style: AppType.meta(context).copyWith(color: c.onHeroMuted),
          ),
        ],
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
        child: Text(text, style: AppType.section(context)),
      );
}
