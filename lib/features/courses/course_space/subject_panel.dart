// lib/features/courses/course_space/subject_panel.dart
//
// The subject page's panels (SubjectProfile: lesson, live, chat, bot, دفتر, schedule): on a phone a tall bottom
// sheet, on a wide window a drawer from the end side (820 for the lesson / schedule, 520 for the rest). One frame:
// the title and a round close button over a hairline, then the panel's own body, which brings its own scroll and,
// when it has one, its own footer ([SubjectPanelFooter]).
//
// The booking group (BK) fills the chat, bot and schedule panels through [SubjectPanelSlots]; this file stays the
// one place that knows how a panel opens.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';

/// The width of a wide panel (the lesson with its video, the schedule's month).
const double kSubjectPanelWide = 820;

/// The width of a narrow panel (chat, bot, دفتر).
const double kSubjectPanelNarrow = 520;

/// How tall the phone sheet is, as a share of the screen: a panel is a place to work in, not a short question.
const double kSubjectPanelPhoneHeight = 0.92;

/// Opens [child] as a subject panel titled [title]. [wide] picks the 820 drawer on a wide window.
Future<T?> showSubjectPanel<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context) child,
  bool wide = false,
}) {
  final phone = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
  return showAppSheet<T>(
    context,
    (ctx) => SubjectPanelFrame(
      title: title,
      phone: phone,
      child: Builder(builder: child),
    ),
    mode: phone ? AppSheetMode.bottom : AppSheetMode.side,
    width: wide ? kSubjectPanelWide : kSubjectPanelNarrow,
  );
}

/// The panel's frame: title + close, a hairline, then [child] filling the rest. Public so tests and goldens can pump
/// a panel without a route.
class SubjectPanelFrame extends StatelessWidget {
  const SubjectPanelFrame({super.key, required this.title, required this.child, this.phone = false, this.onClose});

  final String title;
  final Widget child;

  /// On a phone the frame takes [kSubjectPanelPhoneHeight] of the screen (a bottom sheet sizes to its content).
  final bool phone;

  /// Null: pops the route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final frame = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.pageTitle(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: 'close'.tr,
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.kit.line),
        Expanded(child: child),
      ],
    );
    if (!phone) return frame;
    return SizedBox(height: MediaQuery.sizeOf(context).height * kSubjectPanelPhoneHeight, child: frame);
  }
}

/// The pinned bottom row of a panel (the one forward button, or "back to the notebook" + "save"): a hairline over
/// it, the page gutter around it, and the safe area under it.
class SubjectPanelFooter extends StatelessWidget {
  const SubjectPanelFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.kit.line, width: AppBorder.hairline))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
          child: Row(
            children: [
              for (final (i, w) in children.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                w,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
