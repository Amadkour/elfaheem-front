import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/paint_background.dart';

import '../../features/shared/upload/upload_progress_footer.dart';
import '../../features/student/courses/details/components/app_responsive.dart';
import '../helpers.dart';
import 'app_bar.dart';

class BasePage extends StatelessWidget {
  const BasePage({
    super.key,
    required this.child,
    this.background,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBar,
    this.useWebCard = false,
    this.maxWith,  this.enableFooterWidget=true,
  });

  final double? maxWith;
  final Widget child;
  final Color? background;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  final bool useWebCard;
  final bool enableFooterWidget;

  /// Stacks the app-wide background-upload progress footer above whatever
  /// bottomNavigationBar the page already wants, so a video upload started
  /// on any screen stays visible while the teacher navigates elsewhere.
  /// Renders nothing when there are no active uploads.
  Widget? _footerWith(Widget? existing) {
    if (existing == null) return const UploadProgressFooter();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [const UploadProgressFooter(), existing],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the disable list changes (silent FCM push / theme fetch).
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.disableListVersion,
      builder: (context, _, __) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (key case ValueKey(
    value: final v,
    ) when AppConfig.disableList.contains(v)) {
      return Scaffold(
        appBar: ScreenAppBar(title:(key as ValueKey).value.toString().tr,),
        body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🚀',style: TextStyle(fontSize: 70),),
                Text('coming_soon'.tr , style: context.colors.h2.copyWith(color: context.colors.accent2),),
              ],
            )
        ),
      );
    }
    Widget w =  Scaffold(
      appBar: appBar,
      backgroundColor:
      background ??context.colors.background,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar:enableFooterWidget? _footerWith(bottomNavigationBar):null,
      body: Directionality(
        textDirection: Helpers.pageDirection,
        child:DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.colors.radiusXL),
          ),
          child: child,
        ),
      ),
    );

    if (useWebCard && context.width > 599) {
      return Directionality(
        textDirection: Helpers.pageDirection,
        child: Scaffold(
          backgroundColor:
          background ??(context.colors.background),
          // NOTE: no footer here — `w` below already carries it via its own
          // bottomNavigationBar, and `w` is what actually renders in this
          // branch (nested inside the centered card).

          body: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ElearningPatternPainter(
                    color: context.colors.primaryLight.withValues(alpha:0.2),
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
                    //   color: context.colors.primary,
                    //   width: 1,
                    // ),
                    borderRadius: BorderRadius.circular(context.colors.radiusXL),
                    color: context.colors.background,
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
        ),
      );
    }

    return  w;
  }
}