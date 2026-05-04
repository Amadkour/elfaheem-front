import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/app_theme.dart';

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
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: ExpansionTile(
        controller: controller,
        shape: Border.all(style: BorderStyle.none),
        title: Text(
          initValue == null ? label : initValue!['text'].toString().tr,
          style:  TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w100,
            fontSize: 17,
            color: context.colors.textMedium,
          ),
        ),
        children: List.generate(
            options.length,
            (int i) => Column(
                  children: [
                    DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.white),
                      child: ListTile(
                        leading: haveLogo
                            ? (Image.network(
                                options[i]['logo'],
                                width: 25,
                                height: 25,
                                errorBuilder: (q, w, e) => Icon(Icons.category),
                              ))
                            : null,
                        title: Text(
                          options[i]['text'].toString().tr,
                          style:  TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w100,
                            fontSize: 17,
                            color: context.colors.textMedium,
                          ),
                        ),
                        onTap: () => onChange(i),
                      ),
                    ),
                    i < options.length - 1
                        ? const Divider(height: 0)
                        : SizedBox.shrink()
                  ],
                )),
      ),
    );
  }
}
