import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';

import '../../config/app_config.dart' as Helpers;

class BasePage extends StatelessWidget {
  const BasePage({super.key, required this.child, this.background, this.floatingActionButton, this.bottomNavigationBar, this.appBar});

  final Widget child;
  final Color? background;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  @override
  Widget build(BuildContext context) {
    return Directionality(
        textDirection: Helpers.pageDirection,
        child: Scaffold(
          appBar: appBar,
            backgroundColor: background?? context.colors.background,
            floatingActionButton: floatingActionButton,
            bottomNavigationBar: bottomNavigationBar,
            body: child));
  }
}
