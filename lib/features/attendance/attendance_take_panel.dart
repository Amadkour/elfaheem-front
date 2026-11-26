// lib/features/attendance/attendance_take_panel.dart
//
// "Take attendance" (Tea1Class.dc.html?screen=attendance): ONE card with two steps, from plain values: pick the
// lesson (today's, else the next, is chosen already), then how to take it: the code on the screen, a QR, or by hand
// (the manual register is its own page, so it needs the course: drawn only when [manualAvailable]). One filled
// button starts it. The projector code, the QR and the manual register are three separate views, never one screen.
// Teacher pages use the restrained motion only (M9 presses). The launcher (teacher_attendance_launcher.dart) wires
// it to the sheets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttView;
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/courses/course_profile/t1_class_parts.dart' show ClOptionCard;

class AttendanceTakePanel extends StatefulWidget {
  const AttendanceTakePanel({super.key, required this.sessions, required this.onStart, this.manualAvailable = false, this.nowUtc});

  /// In course order (1 … n).
  final List<LauncherSession> sessions;

  /// The manual register needs the course; without it the third way is not drawn.
  final bool manualAvailable;

  /// Starts [view] for [session].
  final void Function(LauncherSession session, AttView view) onStart;

  /// Fixed "now" for tests.
  final DateTime? nowUtc;

  @override
  State<AttendanceTakePanel> createState() => _AttendanceTakePanelState();
}

class _AttendanceTakePanelState extends State<AttendanceTakePanel> {
  late final DateTime _now = widget.nowUtc ?? DateTime.now().toUtc();
  late final List<LauncherSession> _ordered = launcherOrder(widget.sessions, nowUtc: _now);
  late int? _selected = launcherFocusId(widget.sessions, nowUtc: _now) ?? (_ordered.isEmpty ? null : _ordered.first.id);
  AttView _view = AttView.code;

  LauncherSession? get _session => [for (final s in _ordered) if (s.id == _selected) s].firstOrNull;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focusId = launcherFocusId(widget.sessions, nowUtc: _now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Semantics(header: true, child: Text(attT('t1_cl_take_title'), style: AppType.pageTitle(context)))),
        AppSpace.gapXs,
        Flexible(child: AppTag(attT('t1_cl_one_of_three'), c.primary)),
      ]),
      AppSpace.gapMd,
      _StepHead(number: 1, title: attT('t1_cl_pick_lesson')),
      AppSpace.gapSm,
      if (_ordered.isEmpty)
        AppEmpty(icon: Icons.event_busy_outlined, title: attT('att_launch_empty'))
      else
        SizedBox(
          height: AppTouch.primary * 2 + AppSpace.lg,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _ordered.length,
            separatorBuilder: (_, _) => AppSpace.gapXs,
            itemBuilder: (_, i) {
              final s = _ordered[i];
              final today = launcherIsToday(s, nowUtc: _now);
              final tag = today ? attT('att_launch_today') : (s.id == focusId ? attT('att_launch_next') : null);
              return _LessonCard(
                name: s.name,
                number: s.number,
                when: s.date == null ? null : AppTime.date(s.date!, pattern: 'EEE d MMM'),
                tag: tag,
                selected: s.id == _selected,
                onTap: () => setState(() => _selected = s.id),
              );
            },
          ),
        ),
      AppSpace.gapLg,
      _StepHead(number: 2, title: attT('t1_cl_how')),
      AppSpace.gapSm,
      ClOptionCard(
        key: const ValueKey('att.view.code'),
        icon: Icons.desktop_windows_outlined,
        title: attT('t1_cl_m_code'),
        subtitle: attT('t1_cl_m_code_d'),
        selected: _view == AttView.code,
        onTap: () => setState(() => _view = AttView.code),
      ),
      AppSpace.gapXs,
      ClOptionCard(
        key: const ValueKey('att.view.qr'),
        icon: Icons.qr_code_2_rounded,
        title: attT('t1_cl_m_qr'),
        subtitle: attT('t1_cl_m_qr_d'),
        selected: _view == AttView.qr,
        onTap: () => setState(() => _view = AttView.qr),
      ),
      if (widget.manualAvailable) ...[
        AppSpace.gapXs,
        ClOptionCard(
          key: const ValueKey('att.view.manual'),
          icon: Icons.checklist_rounded,
          title: attT('t1_cl_m_manual'),
          subtitle: attT('t1_cl_m_manual_d'),
          selected: _view == AttView.manual,
          onTap: () => setState(() => _view = AttView.manual),
        ),
      ],
      AppSpace.gapLg,
      AppButton.primary(
        key: const ValueKey('att.start'),
        expand: true,
        size: AppButtonSize.lg,
        icon: _view == AttView.manual ? Icons.checklist_rounded : Icons.qr_code_2_rounded,
        label: attT('t1_cl_start'),
        onPressed: _session == null ? null : () => widget.onStart(_session!, _view),
      ),
    ]);
  }
}

/// The numbered step label: a small round number and the question.
class _StepHead extends StatelessWidget {
  const _StepHead({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        width: AppIconSize.xl,
        height: AppIconSize.xl,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
        child: Text('$number', style: AppType.label(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w600)),
      ),
      AppSpace.gapXs,
      Expanded(child: Text(title, style: AppType.section(context))),
    ]);
  }
}

/// One lesson of the first step: its date, its name and, for today's or the next, a tag.
class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.name, required this.number, required this.selected, required this.onTap, this.when, this.tag});

  final String name;
  final int number;
  final String? when, tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: AppPressScale(
        child: Material(
          color: selected ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: AppTouch.primary * 3,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Row(children: [
                    if (tag != null) ...[AppTag(tag!, c.primary), AppSpace.gapXs],
                    Expanded(child: Text(when ?? '#$number', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
                  ]),
                  const SizedBox(height: AppSpace.xxs),
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
