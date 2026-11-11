import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/design/app_buttons.dart';

/// The older "Refresh" pill: now the kit's tonal button (the emerald tint, emerald ink), small, with the kit's
/// spinner over the label while [onTap] runs.
class RefreshButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const RefreshButton({super.key, required this.onTap});

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> {
  bool isRefreshing = false;

  Future<void> _run() async {
    setState(() => isRefreshing = true);
    await widget.onTap.call();
    if (mounted) setState(() => isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppButton.tonal(
      label: isRefreshing ? 'refreshing'.tr : 'refresh'.tr,
      icon: Icons.refresh_rounded,
      size: AppButtonSize.sm,
      busy: isRefreshing,
      onPressed: isRefreshing ? null : _run,
    );
  }
}
