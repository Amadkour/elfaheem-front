// lib/design/app_back_button.dart — THE back button of every page (D-360, D-612).
//
//   AppBackButton()                  pops the nearest navigator: a paper chip in ink on the canvas
//   AppBackButton(onHero: true)      the same button as glass on a hero / gradient surface
//   AppBackButton(onPressed: …)      when leaving needs its own logic
//
// A [ChromePlate]: 48 × 48 tap area around a 40 × 40 plate, one icon that mirrors in Arabic by itself, labelled for
// screen readers, with the kit's press depth.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'chrome_button.dart' show ChromePlate;

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.onHero = false});

  final VoidCallback? onPressed;
  final bool onHero;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'ds_back'.tr,
        child: Semantics(
          button: true,
          label: 'ds_back'.tr,
          excludeSemantics: true,
          onTap: () => _go(context),
          child: ChromePlate(
            onHero: onHero,
            onTap: () => _go(context),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      );

  void _go(BuildContext context) {
    final handler = onPressed;
    if (handler != null) {
      handler();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}
