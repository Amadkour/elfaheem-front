// lib/features/sessions/teacher/components/session_options_sheet.dart
//
// The teacher's ⋮ of a session (Tea1Course "session options"): the session's actions as one kit sheet, a row per
// action (an icon well, the label), the destructive one last and in the danger tone. Plain values: the session
// card builds the options and runs the chosen one after the sheet closed.
//
//   showSessionOptionsSheet(context, title: session.name, options: [SessionOption(...)])  → the chosen id, or null
//   SessionOptionsBody(...)                                                              the sheet's content
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

/// One action of the sheet.
class SessionOption {
  const SessionOption({required this.id, required this.icon, required this.label, this.danger = false, this.good = false});

  final String id;
  final IconData icon;
  final String label;

  /// Delete / end: drawn in the danger tone.
  final bool danger;

  /// Go live: drawn in the success tone.
  final bool good;
}

Future<String?> showSessionOptionsSheet(BuildContext context, {required String title, required List<SessionOption> options}) =>
    showAppSheet<String>(context, (sheet) => SessionOptionsBody(title: title, options: options, onPick: (id) => Navigator.of(sheet).pop(id)));

class SessionOptionsBody extends StatelessWidget {
  const SessionOptionsBody({super.key, required this.title, required this.options, required this.onPick});

  final String title;
  final List<SessionOption> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    return AppSheetContent(
      icon: Icons.more_horiz_rounded,
      title: title,
      subtitle: ar ? 'خيارات الحصة' : 'Session options',
      children: [
        for (final (i, o) in options.indexed) ...[
          if (o.danger && i > 0) ...[
            const SizedBox(height: AppSpace.xs),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            const SizedBox(height: AppSpace.xs),
          ],
          _Row(option: o, onTap: () => onPick(o.id)),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.option, required this.onTap});

  final SessionOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = option.danger ? c.danger : (option.good ? c.success : c.primary);
    final ink = option.danger ? appInk(context, c.danger) : c.textDark;
    return Semantics(
      button: true,
      label: option.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('session_option.${option.id}'),
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Row(children: [
                Container(
                  width: AppDashSize.glyph - AppSpace.xs,
                  height: AppDashSize.glyph - AppSpace.xs,
                  decoration: BoxDecoration(
                    color: appTintOn(context, tone, surface: c.cardBg),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(option.icon, size: AppIconSize.md, color: appInk(context, tone)),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(option.label,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
