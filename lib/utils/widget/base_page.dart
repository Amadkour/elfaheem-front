import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/paint_background.dart';

import '../../features/student/courses/details/components/app_responsive.dart';
import '../helpers.dart';

class BasePage extends StatelessWidget {
  const BasePage({
    super.key,
    required this.child,
    this.background,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBar,
    this.useWebCard = false,
    this.maxWith,
  });

  final double? maxWith;
  final Widget child;
  final Color? background;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  final bool useWebCard;

  @override
  Widget build(BuildContext context) {
    Widget w = Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        appBar: appBar,
        backgroundColor:
        background ??(context.showSidebar?context.themeConfig.background.withValues(alpha: 0.5):context.themeConfig.background),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.colors.radiusXL),
          ),
          child: child,
        ),
      ),
    );

    if (useWebCard && context.width > 599) {
      return Scaffold(
        backgroundColor:
            background ??(context.showSidebar?context.themeConfig.background.withValues(alpha: 0.5):context.themeConfig.background),

        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: ElearningPatternPainter(
                  color: context.themeConfig.accent.withValues(alpha: 0.05),
                  width: Helpers.calculateRemainingWidth(context),
                ),
              ),
            ),
            Align(
              alignment: AlignmentGeometry.center,
              child: Container(
                width: Helpers.calculateRemainingWidth(
                  context,
                  maxWith: maxWith,
                ),
                margin: EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(0.0),
                decoration: BoxDecoration(
                  // border: BoxBorder.all(
                  //   color: context.themeConfig.primary,
                  //   width: 1,
                  // ),
                  borderRadius: BorderRadius.circular(context.colors.radiusXL),
                  color: context.themeConfig.background,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadiusGeometry.circular(
                    context.colors.radiusXL,
                  ),
                  child: w,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return w;
  }
}
