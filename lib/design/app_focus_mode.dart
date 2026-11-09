// lib/design/app_focus_mode.dart — full-space focus mode on the web and desktop (D-360).
//
// While on, the role shell hides its sidebar / rail and top bar and every header stays compact, so the page gets the
// whole window. The choice is remembered on this device. Phones have no side chrome, so the toggle hides itself there.
//
//   AppFocusToggle(onHero: true)     the enter / leave button: ALWAYS the last button at the end of the header (D-551)
//   AppFocusExitButton()             the labelled way out, in the same corner, on the slim bar focus mode leaves
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_responsive.dart';
import 'app_shell_nav.dart' show ShellScope;
import 'app_tokens.dart';
import 'chrome_button.dart';

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
    return ValueListenableBuilder<bool>(
      valueListenable: AppFocusMode.instance,
      builder: (context, on, _) {
        final button = ChromeIconButton(
          icon: on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: (on ? 'ds_focus_exit' : 'ds_focus_enter').tr,
          onTap: AppFocusMode.instance.toggle,
        );
        return onHero ? ChromeBar(child: button) : button;
      },
    );
  }
}

/// The labelled way out of focus mode, on the shell's slim bar, in the corner where focus mode was entered.
class AppFocusExitButton extends StatelessWidget {
  const AppFocusExitButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.chip + 4);
    return Material(
      key: const ValueKey('app.focus.exit'),
      color: c.heroGlass,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.heroGlassBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: AppFocusMode.instance.toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fullscreen_exit_rounded, size: AppIconSize.md, color: c.onHero),
              const SizedBox(width: AppSpace.xs),
              Text('ds_focus_exit'.tr, maxLines: 1, style: AppType.label(context).copyWith(color: c.onHero)),
            ]),
          ),
        ),
      ),
    );
  }
}
