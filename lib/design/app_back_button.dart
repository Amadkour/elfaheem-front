// lib/design/app_back_button.dart — THE back button of every page (D-360).
//
//   AppBackButton()                  pops the nearest navigator (a page on the normal background)
//   AppBackButton(onHero: true)      the same button on a gradient header
//   AppBackButton(onPressed: …)      when leaving needs its own logic
//
// 48 × 48 tap area around a 40 × 40 plate, one icon that mirrors in Arabic by itself, labelled for screen readers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_tokens.dart';

class AppBackButton extends StatefulWidget {
  const AppBackButton({super.key, this.onPressed, this.onHero = false});

  final VoidCallback? onPressed;
  final bool onHero;

  @override
  State<AppBackButton> createState() => _AppBackButtonState();
}

class _AppBackButtonState extends State<AppBackButton> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plate = widget.onHero ? c.heroGlass : c.inputBg;
    final ink = widget.onHero ? c.onHero : c.textDark;
    final radius = BorderRadius.circular(AppRadius.chip + 2);
    return SizedBox(
      width: AppTouch.min,
      height: AppTouch.min,
      child: Tooltip(
        message: 'ds_back'.tr,
        child: Semantics(
          button: true,
          label: 'ds_back'.tr,
          excludeSemantics: true,
          onTap: _go,
          child: Center(
            child: AnimatedScale(
              scale: _down ? 0.92 : 1,
              duration: AppMotion.of(context).fast,
              curve: AppMotion.curve,
              child: Material(
                color: plate,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: widget.onHero ? BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline) : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _go,
                  onHighlightChanged: _press,
                  child: SizedBox(
                    width: AppTouch.min - AppSpace.xs,
                    height: AppTouch.min - AppSpace.xs,
                    child: Icon(Icons.arrow_back_rounded, size: AppIconSize.md, color: ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _go() {
    final handler = widget.onPressed;
    if (handler != null) {
      handler();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}
