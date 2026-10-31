// lib/design/studio/studio_small_screen.dart
//
// The graceful phone case: the full editor needs room (a page, a toolbar and a property panel), so below
// [StudioSmallScreenGate.minWidth] it first says so — calmly, with "Continue anyway" — instead of squeezing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_kit.dart' show AppPrimaryButton, appText;
import '../app_tokens.dart';

/// "The full editor works best on a tablet or computer" with Continue anyway (and an optional way back).
class StudioSmallScreenNotice extends StatelessWidget {
  const StudioSmallScreenNotice({super.key, required this.onContinue, this.onBack, this.title, this.message});

  final VoidCallback onContinue;

  /// Shown as a quiet text button under the primary one (e.g. Navigator.pop).
  final VoidCallback? onBack;
  final String? title, message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              child: Icon(Icons.devices_rounded, size: 34, color: c.primary),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              title ?? translate('studio_small_title'),
              textAlign: TextAlign.center,
              style: AppType.pageTitle(context),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              message ?? translate('studio_small_body'),
              textAlign: TextAlign.center,
              style: appText(14, w: FontWeight.w400, c: c.textMedium, h: 1.5),
            ),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(label: translate('studio_small_continue'), onPressed: onContinue),
            ),
            if (onBack != null) ...[
              const SizedBox(height: AppSpace.xs),
              TextButton(
                onPressed: onBack,
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                child: Text(translate('studio_small_back'), style: appText(14, w: FontWeight.w600, c: c.primary)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Shows [StudioSmallScreenNotice] while the available width is under [minWidth] and the person has not chosen
/// to continue; then (or on a wide screen) [child].
class StudioSmallScreenGate extends StatefulWidget {
  const StudioSmallScreenGate({super.key, required this.child, this.minWidth = 600, this.onBack});

  final Widget child;
  final double minWidth;
  final VoidCallback? onBack;

  @override
  State<StudioSmallScreenGate> createState() => _StudioSmallScreenGateState();
}

class _StudioSmallScreenGateState extends State<StudioSmallScreenGate> {
  bool _continued = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => _continued || box.maxWidth >= widget.minWidth
            ? widget.child
            : StudioSmallScreenNotice(onContinue: () => setState(() => _continued = true), onBack: widget.onBack),
      );
}
