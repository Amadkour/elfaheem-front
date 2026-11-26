// lib/features/live/room/student/student_room_view.dart
//
// The student's private live room (SubjectProfile live + fullscreen live; RULES 1.7, backend D-1950). A student in a
// course class sees the stage — the teacher's camera, screen or board — with the teacher's small camera tile on it,
// "أنت والمعلم" and four controls: the microphone (off until the teacher gives the floor), the hand, a question to the
// teacher, and "اطلع من الحصة". No participant list, no count, no other tile, no chat author.
//
//   normal       the header (lesson · the live tag · minimize) → the framed stage → "أنت والمعلم" → the controls
//   fullscreen   the stage edge to edge, one bar under it: who · hand · leave · "صغّر"
//
// Plain values: the room (room.dart) passes the stage widget and its overlays, the state and the callbacks.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/live/room/student/student_live_api.dart' show kLiveAskMaxLength;
import 'package:flutter_education_app/features/live/room/student/student_live_parts.dart';

/// The frame around the stage (the reference's navy bezel).
const double _kBezel = AppSpace.xs;

/// The small round avatar of "أنت والمعلم".
const double _kWhoAvatar = AppTouch.min;

class StudentRoomView extends StatelessWidget {
  const StudentRoomView({
    super.key,
    required this.lessonTitle,
    required this.stage,
    required this.micOn,
    required this.micAllowed,
    required this.handUp,
    required this.fullScreen,
    required this.onToggleFullScreen,
    required this.onLeave,
    this.teacherName,
    this.liveFor,
    this.stageOverlays = const [],
    this.onToggleMic,
    this.onToggleHand,
    this.onAsk,
    this.onMinimize,
    this.handBusy = false,
  });

  final String lessonTitle;
  final String? teacherName;

  /// "05:12": how long the class has been live; null hides the clock.
  final String? liveFor;

  /// The stage (the room's main view: the teacher's video, the shared screen or the board) and what sits on it
  /// (the teacher's camera tile, the board dock …), laid out in one Stack.
  final Widget stage;
  final List<Widget> stageOverlays;

  final bool micOn;

  /// The teacher brought the student on stage: the microphone may be used.
  final bool micAllowed;
  final bool handUp;
  final bool handBusy;
  final bool fullScreen;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleHand;
  final VoidCallback? onAsk;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onLeave;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
        budget: false,
        child: StudentLiveSurface(
          child: SafeArea(child: fullScreen ? _full(context) : _normal(context)),
        ),
      );

  Widget _stageBox(BuildContext context, {required bool framed}) {
    final c = context.colors;
    final stack = Stack(fit: StackFit.expand, children: [stage, ...stageOverlays]);
    if (!framed) return stack;
    return Container(
      padding: const EdgeInsets.all(_kBezel),
      decoration: BoxDecoration(
        color: c.kit.ink,
        borderRadius: BorderRadius.circular(AppRadius.block + _kBezel),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.block),
        child: Stack(
          fit: StackFit.expand,
          children: [
            stack,
            PositionedDirectional(
              bottom: AppSpace.sm,
              start: AppSpace.sm,
              child: _ChromeDisc(
                icon: Icons.fullscreen_rounded,
                tooltip: 'sb_live_fullscreen'.tr,
                onTap: onToggleFullScreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _normal(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final gutter = AppSpace.gutter(box.maxWidth);
          final wide = box.maxWidth >= Breakpoints.mobile;
          return Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(lessonTitle: lessonTitle, liveFor: liveFor, onMinimize: onMinimize),
                const SizedBox(height: AppSpace.md),
                Expanded(child: _stageBox(context, framed: true)),
                const SizedBox(height: AppSpace.md),
                if (wide)
                  Row(
                    children: [
                      Expanded(child: StudentLiveWho(teacherName: teacherName)),
                      _controls(context),
                    ],
                  )
                else ...[
                  StudentLiveWho(teacherName: teacherName),
                  const SizedBox(height: AppSpace.md),
                  Center(child: _controls(context)),
                ],
              ],
            ),
          );
        },
      );

  Widget _full(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _stageBox(context, framed: false)),
        Container(
          color: c.kit.deep,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Row(
            children: [
              Expanded(child: StudentLiveWho(teacherName: teacherName, compact: true)),
              const SizedBox(width: AppSpace.sm),
              Flexible(
                flex: 2,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    _handButton(),
                    _leaveButton(context),
                    TextButton.icon(
                      onPressed: onToggleFullScreen,
                      style: TextButton.styleFrom(foregroundColor: c.onHero, minimumSize: const Size(0, AppTouch.min)),
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: AppIconSize.md),
                      label: Text('sb_live_minimize'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _handButton() => StudentLiveRoundButton(
        icon: Icons.back_hand_outlined,
        tooltip: handUp ? 'sb_live_hand_down'.tr : 'sb_live_hand_up'.tr,
        selected: handUp,
        tone: handUp ? StudentLiveTone.warm : StudentLiveTone.glass,
        size: AppTouch.primary,
        onTap: handBusy ? null : onToggleHand,
      );

  Widget _leaveButton(BuildContext context) {
    final kit = context.colors.kit;
    return AppJelly(
      child: Material(
        color: kit.live.tint,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onLeave,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'sb_live_leave'.tr,
                  maxLines: 1,
                  style: AppType.label(context).copyWith(color: kit.live.ink, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          StudentLiveRoundButton(
            icon: micOn && micAllowed ? Icons.mic_rounded : Icons.mic_off_rounded,
            tooltip: !micAllowed ? 'sb_live_mic_wait'.tr : (micOn ? 'sb_live_mic_on'.tr : 'sb_live_mic_off'.tr),
            selected: micOn && micAllowed,
            size: AppTouch.primary,
            onTap: micAllowed ? onToggleMic : null,
          ),
          _handButton(),
          StudentLiveRoundButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'sb_live_ask'.tr,
            size: AppTouch.primary,
            onTap: onAsk,
          ),
          _leaveButton(context),
        ],
      );
}

/// "أنت والمعلم" with the teacher's initial: the only "who is here" a student is shown.
class StudentLiveWho extends StatelessWidget {
  const StudentLiveWho({super.key, this.teacherName, this.compact = false});

  final String? teacherName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'sb_live_you_and_teacher'.tr,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudentLiveAvatar(name: teacherName, size: compact ? AppDashSize.ringSm : _kWhoAvatar),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Text(
              'sb_live_you_and_teacher'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.tileTitle(context).copyWith(color: c.onHero),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lessonTitle, this.liveFor, this.onMinimize});

  final String lessonTitle;
  final String? liveFor;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              lessonTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.pageTitle(context).copyWith(color: c.onHero),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: AppLiveTag(
            onDark: true,
            slap: false,
            label: liveFor == null ? null : sbLiveTr('sb_live_live_for', {'time': liveFor!}),
          ),
        ),
        if (onMinimize != null) ...[
          const SizedBox(width: AppSpace.xs),
          AppIconButton(
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: 'sb_live_minimize_box'.tr,
            onHero: true,
            onPressed: onMinimize!,
          ),
        ],
      ],
    );
  }
}

class _ChromeDisc extends StatelessWidget {
  const _ChromeDisc({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.kit.deep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          onTap: onTap,
          child: SizedBox(
            width: AppTouch.min,
            height: AppTouch.min,
            child: Icon(icon, color: c.onHero, size: AppIconSize.lg),
          ),
        ),
      ),
    );
  }
}

/// The question to the teacher: one field, sent to the teacher only. Resolves to the text, or null.
Future<String?> showStudentAskSheet(BuildContext context) {
  final ctrl = TextEditingController();
  return showAppSheet<String>(
    context,
    (ctx) => AppSheetContent(
      title: 'sb_live_ask'.tr,
      icon: Icons.chat_bubble_outline_rounded,
      children: [
        AppField(
          controller: ctrl,
          label: 'sb_live_ask_label'.tr,
          hint: 'sb_live_ask_hint'.tr,
          maxLength: kLiveAskMaxLength,
          maxLines: 4,
        ),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(
          label: 'sb_live_ask_send'.tr,
          icon: Icons.send_rounded,
          expand: true,
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}
