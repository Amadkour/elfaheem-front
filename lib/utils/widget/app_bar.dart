import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/helpers.dart';

import '../../config/app_theme.dart';

class ScreenAppBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  const ScreenAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            if (showBack)
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.colors.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: context.colors.cardShadow,
                  ),
                  child:  Icon(
                    Icons.arrow_back,
                    color: context.colors.textDark,
                    size: 22,
                  ),
                ),
              ),
            if (showBack) const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: context.colors.h2,
                textAlign: showBack ? TextAlign.right : TextAlign.right,
              ),
            ),
            SizedBox(width: 10,),
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }
}
