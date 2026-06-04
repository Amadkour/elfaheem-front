import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';

class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? itemBackground;
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,  this.itemBackground,

  });

  @override
  Widget build(BuildContext context) {
    Widget mainWidgets=Padding(
        padding:const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: children.map((child) {
          final idx = children.indexOf(child);
          return Column(
            children: [
              child,
              if (idx < children.length - 1)
                Divider(
                    height: 1, color: context.colors.divider, indent: 48),
            ],
          );
        }).toList(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          child: Text(title,
              style: context.colors.h3
                  .copyWith(color: context.colors.textMedium, fontSize: 14)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            color:context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            boxShadow: context.colors.cardShadow,
          ),
          child: itemBackground==null? mainWidgets: DecoratedBox(decoration:BoxDecoration(
              color: itemBackground!,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),

          ) ,
          child: mainWidgets,) ,
        ),
      ],
    );
  }
}