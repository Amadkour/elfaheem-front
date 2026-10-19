import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/parent/parent_widgets.dart';

class ScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final Color? background;
  final Color? titleColor;

  const ScreenAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.background,
    this.titleColor,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Follow the app language: Arabic = back button + title on the right,
    // English = on the left. Actions land on the opposite side automatically.
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: AppBar(
        backgroundColor: background ?? c.background,
        automaticallyImplyLeading: false,
        centerTitle: false,
        leading: showBack
            ? GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  // CupertinoIcons.back mirrors by itself with the direction.
                  child: Icon(CupertinoIcons.back, color: c.textDark, size: 20),
                ),
              )
            : null,
        title: Text(
          title,
          textAlign: TextAlign.start,
          style: c.h2.copyWith(fontFamily: 'bahji',color: titleColor),
        ),
        actions: actions,
      ),
    );
  }
}
