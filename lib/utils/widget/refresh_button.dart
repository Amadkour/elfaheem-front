
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';

class RefreshButton extends StatefulWidget {
  final Future<void> Function() onTap;
   const RefreshButton({super.key, required this.onTap});

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool         isRefreshing=false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
  }

  @override
  void didUpdateWidget(RefreshButton old) {
    super.didUpdateWidget(old);
    if (isRefreshing && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!isRefreshing && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:isRefreshing ? null :()
    async {
      setState(() {
        isRefreshing=true;
      });
      await widget.onTap.call();
      setState(() {
       isRefreshing=false;
      });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isRefreshing ? null : context.themeConfig.linearPrimary,
          color:    isRefreshing
              ? context.themeConfig.primary.withValues(alpha: 0.1)
              : null,
          borderRadius: BorderRadius.circular(22),
          boxShadow: isRefreshing ? null : context.themeConfig.primaryShadow(isDark:context.colors.isDark),
          // boxShadow: null ,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RotationTransition(
            turns: _ctrl,
            child: Icon(
              Icons.refresh_rounded,
              size: 16,
              color: isRefreshing ? context.themeConfig.primaryDark : Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRefreshing ? 'refreshing'.tr : 'refresh'.tr,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isRefreshing ? context.themeConfig.primaryDark : Colors.white,
            ),
          ),
        ]),
      ),
    );
  }
}
