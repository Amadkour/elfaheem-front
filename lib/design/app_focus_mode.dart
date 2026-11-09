// lib/design/app_focus_mode.dart — full-space focus mode on the web and desktop (D-360).
//
// While on, the role shell hides its sidebar / rail and top bar and every header stays compact, so the page gets the
// whole window. The choice is remembered on this device. Phones have no side chrome, so the toggle hides itself there.
//
//   AppFocusToggle(onHero: true)     the enter / leave icon (headers and the shell's top bar carry it already)
//   AppFocusExitPill()               the labelled way out the shell floats while focus mode is on
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_responsive.dart';
import 'app_shell_nav.dart' show ShellScope;
import 'app_tokens.dart';

class AppFocusMode extends ValueNotifier<bool> {
  AppFocusMode._() : super(false);

  static final AppFocusMode instance = AppFocusMode._();
  static const String prefKey = 'ui.focus_mode.v1';

  bool _loaded = false;

  /// Reads the remembered choice once.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      value = p.getBool(prefKey) ?? false;
    } catch (_) {
      // no storage (private window): the mode just is not remembered
    }
  }

  Future<void> toggle() async {
    value = !value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefKey, value);
    } catch (_) {
      // see ensureLoaded
    }
  }

  /// Whether focus mode changes anything at this window width.
  static bool availableAt(double width) => width >= Breakpoints.mobile;

  /// Focus mode is on and applies to this window.
  static bool activeIn(BuildContext context) => instance.value && availableAt(MediaQuery.sizeOf(context).width);

  @visibleForTesting
  void debugReset() {
    _loaded = false;
    value = false;
  }
}

/// Enters or leaves focus mode. Draws nothing where there is no side chrome to hide (phones, pages outside a shell).
class AppFocusToggle extends StatelessWidget {
  const AppFocusToggle({super.key, this.onHero = false});

  final bool onHero;

  @override
  Widget build(BuildContext context) {
    if (!AppFocusMode.availableAt(MediaQuery.sizeOf(context).width) || ShellScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return ValueListenableBuilder<bool>(
      valueListenable: AppFocusMode.instance,
      builder: (context, on, _) => IconButton(
        tooltip: (on ? 'ds_focus_exit' : 'ds_focus_enter').tr,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        onPressed: AppFocusMode.instance.toggle,
        icon: Icon(on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            size: AppIconSize.lg, color: onHero ? c.onHero : c.textMedium),
      ),
    );
  }
}

/// The floating, labelled way out of focus mode.
class AppFocusExitPill extends StatelessWidget {
  const AppFocusExitPill({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.sheet);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 3)),
      child: Material(
        key: const ValueKey('app.focus.exit'),
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: AppFocusMode.instance.toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fullscreen_exit_rounded, size: AppIconSize.md, color: c.primary),
                const SizedBox(width: AppSpace.xs),
                Text('ds_focus_exit'.tr, maxLines: 1, style: AppType.label(context).copyWith(color: c.textDark)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
