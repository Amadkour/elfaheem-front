import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/features/parent/parent_widgets.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';

class ScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  /// Kept for existing callers: every page wears the same header (D-360).
  final Color? background;
  final Color? titleColor;

  /// The page id of the Info button (help entry); null = no button.
  final String? helpPageId;

  const ScreenAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.background,
    this.titleColor,
    this.helpPageId,
  });

  AppHeader get _header => AppHeader(
        title: title,
        showBack: showBack,
        actions: [...?actions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!)],
      );

  @override
  Size get preferredSize => _header.preferredSize;

  // Follows the app language: Arabic = back button and title on the right, English = on the left.
  @override
  Widget build(BuildContext context) => Directionality(textDirection: Helpers.pageDirection, child: _header);
}
