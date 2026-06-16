import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_theme.dart';

class ScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final Color? background;

  const ScreenAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.background,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBar(
      backgroundColor: background ?? c.cardBg,
      automaticallyImplyLeading: false,
      leading: showBack
          ? GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: c.cardShadow,
          ),
          child: Icon(
            CupertinoIcons.back,
            color: c.textDark,
            size: 20,
          ),
        ),
      )
          : null,
      title: Text(
        title,
        style: c.h2.copyWith(fontFamily: 'bahji'),
        textAlign: TextAlign.right,
      ),
      actions: actions,
    );
  }
}