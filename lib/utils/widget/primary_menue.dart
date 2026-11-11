import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

class MyPrimaryMenu extends StatelessWidget {
  const MyPrimaryMenu(
      {super.key,
      required this.controller,
      required this.initValue,
      required this.options,
      required this.haveLogo,
      required this.onChange,
      required this.label});

  final ExpansibleController controller;
  final Map? initValue;
  final List<Map> options;
  final bool haveLogo;
  final String label;
  final void Function(int) onChange;

  @override
  Widget build(BuildContext context) {
    return Material(
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.25),
      color: context.colors.inputBg,
      borderRadius: BorderRadius.circular(AppRadius.control),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(

        controller: controller,
        shape: Border.all(style: BorderStyle.none),
        title: Text(
          initValue == null ? label : initValue!['text'].toString().tr,
          style: AppType.row(context).copyWith(
            color: context.colors.textDark,
          ),
        ),
        children: List.generate(
            options.length,
            (int i) => Column(
                  children: [
                    Material( // not a coloured DecoratedBox: it hid the tile colour / ink (ListTile asserts)
                      color: context.colors.background,
                      child: ListTile(
                        tileColor: context.colors.inputBg,
                        splashColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        leading: haveLogo
                            ? (Image.network(
                                options[i]['logo'],
                                width: AppIconSize.lg,
                                height: AppIconSize.lg,
                                errorBuilder: (q, w, e) => Icon(Icons.category),
                              ))
                            : null,
                        title: Text(
                          options[i]['text'].toString().tr,
                          style: AppType.row(context).copyWith(
                            color: context.colors.textMedium,
                          ),
                        ),
                        trailing:(initValue?['text']==options[i]['text'])?
                        Icon( CupertinoIcons.check_mark_circled_solid,color: context.colors.primary,):
                        Icon( CupertinoIcons.circle,color: context.colors.secondText,),
                        onTap: () => onChange(i),
                      ),
                    ),
                    i < options.length - 1
                        ? Divider(height: 0, thickness: AppBorder.hairline, color: context.colors.divider)
                        : SizedBox.shrink()
                  ],
                )),
      ),
    );
  }
}
